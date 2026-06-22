# Upgrade libvirt provider from 0.8.3 to 0.9.7

## Why

Provider 0.8.3 generates broken XML for aarch64 UEFI guests on libvirt 9.x hosts.
When `firmware` is set, it emits `<os firmware='efi'>` which triggers libvirt's
firmware autoselection mode, which then rejects `readonly` and `type` on `<loader>`.

The current workaround is an XSLT rule in `main.tf` that strips `firmware='efi'`
from `<os>` at apply time. This is fragile — it patches generated XML rather than
setting things correctly.

Provider 0.9.1 redesigned `libvirt_domain` to map HCL fields directly to libvirt
XML without conflating the firmware path with the autoselection attribute.
Versions 0.9.4+ also handle NVRAM file cleanup correctly during destroy/recreate
using `VIR_DOMAIN_UNDEFINE_NVRAM`.

Latest stable: **0.9.7** (March 2026).

---

## Breaking changes summary (0.8.3 → 0.9.x)

The `libvirt_domain` resource schema was redesigned in 0.9.0. It is not
backwards-compatible. The key changes affecting this project:

| What | 0.8.3 | 0.9.7 |
|---|---|---|
| CPU architecture | top-level `arch` | `os { type_arch = "..." }` |
| Machine type | top-level `machine` | `os { type_machine = "..." }` |
| Domain type (qemu/kvm) | top-level `type` | top-level `type` — unchanged |
| Firmware path | top-level `firmware` | `os { loader = "..." }` |
| Loader type | XSLT workaround | `os { loader_type = "pflash" }` |
| Loader readonly | XSLT workaround | `os { loader_readonly = "yes" }` |
| Firmware autoselection | `firmware='efi'` injected by provider bug | `os { firmware = "efi" }` — explicit opt-in |
| NVRAM | top-level `nvram { file template }` | `os { nv_ram { file template } }` |
| XSLT block | `xml { xslt = "..." }` | still supported (top-level) |
| `cloudinit` | top-level attribute | top-level attribute — unchanged |

The `libvirt_pool`, `libvirt_volume`, `libvirt_network`, `libvirt_cloudinit_disk`,
and `null_resource` resources are unaffected.

---

## Migration plan

### Step 1 — Destroy existing domains

State drift accumulated during the 0.8.3 deployment. Before upgrading the
provider, destroy only the domain resources (leave volumes/network/pool intact
to avoid re-downloading the image):

```bash
tofu destroy \
  -target 'libvirt_domain.domain-distro[0]' \
  -target 'libvirt_domain.domain-distro[1]' \
  -target 'libvirt_domain.domain-distro[2]' \
  -var 'arch=aarch64' \
  -var 'source_vm=sources/debian13-arm64.qcow2' \
  -var 'interface=enp1s0' \
  -var 'firmware=/usr/share/AAVMF/AAVMF_CODE.fd' \
  -var 'nvram_template=/usr/share/AAVMF/AAVMF_VARS.fd'
```

Verify they are gone:

```bash
virsh -c qemu:///system list --all | grep "db-"
```

### Step 2 — Bump provider version in `main.tf`

```hcl
required_providers {
  libvirt = {
    source  = "dmacvicar/libvirt"
    version = "0.9.7"
  }
}
```

### Step 3 — Rewrite `libvirt_domain` in `main.tf`

Replace the current resource with the 0.9.x schema. The `os {}` block replaces
the top-level `arch`, `machine`, `firmware`, and `nvram` attributes.

**Before (0.8.3):**

```hcl
resource "libvirt_domain" "domain-distro" {
  count   = var.hosts
  name    = var.hostnames[count.index]
  memory  = var.memory[count.index]
  vcpu    = var.vcpu
  arch    = var.arch
  type    = var.domain_type
  machine = local.machine

  firmware = local.is_arm && var.firmware != "" ? var.firmware : null

  dynamic "nvram" {
    for_each = local.is_arm && var.firmware != "" && var.nvram_template != "" ? [1] : []
    content {
      file     = "/var/lib/libvirt/qemu/nvram/${var.hostnames[count.index]}_VARS.fd"
      template = var.nvram_template
    }
  }

  network_interface {
    network_name = "priv"
    addresses    = [var.ips[count.index]]
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  disk {
    volume_id = element(libvirt_volume.worker.*.id, count.index)
  }

  cloudinit = element(libvirt_cloudinit_disk.commoninit.*.id, count.index)

  xml {
    xslt = <<EOF
... (three XSLT rules: IDE removal, cloud-init cdrom→virtio, firmware fix, cortex-a57) ...
EOF
  }
}
```

**After (0.9.7):**

```hcl
resource "libvirt_domain" "domain-distro" {
  count  = var.hosts
  name   = var.hostnames[count.index]
  memory = var.memory[count.index]
  vcpu   = var.vcpu
  type   = var.domain_type

  os {
    type_arch    = var.arch
    type_machine = local.machine

    # UEFI firmware — only set for aarch64
    loader          = local.is_arm && var.firmware != "" ? var.firmware : null
    loader_type     = local.is_arm && var.firmware != "" ? "pflash" : null
    loader_readonly = local.is_arm && var.firmware != "" ? "yes" : null

    dynamic "nv_ram" {
      for_each = local.is_arm && var.firmware != "" && var.nvram_template != "" ? [1] : []
      content {
        file     = "/var/lib/libvirt/qemu/nvram/${var.hostnames[count.index]}_VARS.fd"
        template = var.nvram_template
      }
    }
  }

  network_interface {
    network_name = "priv"
    addresses    = [var.ips[count.index]]
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  disk {
    volume_id = element(libvirt_volume.worker.*.id, count.index)
  }

  cloudinit = element(libvirt_cloudinit_disk.commoninit.*.id, count.index)

  # ARM virt machine does not support IDE bus; convert cloud-init cdrom to virtio disk.
  # The cortex-a57 injection and firmware autoselection workaround are no longer needed.
  dynamic "xml" {
    for_each = local.is_arm ? [1] : []
    content {
      xslt = <<EOF
<?xml version="1.0" ?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output omit-xml-declaration="yes" indent="yes"/>
  <xsl:template match="node()|@*">
    <xsl:copy>
      <xsl:apply-templates select="node()|@*"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="/domain/devices/controller[@type='ide']"/>

  <xsl:template match="/domain/devices/disk[@device='cdrom'][./target[@bus='ide']]">
    <disk type='file' device='disk'>
      <xsl:apply-templates select="driver|source"/>
      <target dev='vdb' bus='virtio'/>
      <readonly/>
    </disk>
  </xsl:template>
</xsl:stylesheet>
EOF
    }
  }
}
```

Key differences:
- `arch` / `machine` move into `os { type_arch type_machine }`
- `firmware` / `nvram` move into `os { loader loader_type loader_readonly nv_ram {} }`
- The cortex-a57 XSLT rule is removed — 0.9.x sets `os.type_arch = "aarch64"` which causes the provider to emit the correct CPU model directly
- The `firmware='efi'` XSLT workaround is removed — it was only needed because 0.8.3 injected that attribute incorrectly
- The IDE→virtio XSLT rule is kept — the `virt` machine type still has no IDE controller and cloud-init still arrives as an IDE CDROM in the provider's default XML

### Step 4 — Remove the now-unused `locals` block entries (optional cleanup)

The `machine` local is still needed. No change required here, but the `is_arm`
local can be simplified if desired since `os.type_arch` now handles arch logic
more cleanly inside the `os {}` block.

### Step 5 — Re-init and apply

```bash
tofu init -upgrade
tofu apply \
  -var 'arch=aarch64' \
  -var 'source_vm=sources/debian13-arm64.qcow2' \
  -var 'interface=enp1s0' \
  -var 'firmware=/usr/share/AAVMF/AAVMF_CODE.fd' \
  -var 'nvram_template=/usr/share/AAVMF/AAVMF_VARS.fd'
```

### Step 6 — Verify

```bash
# Domains running
virsh -c qemu:///system list --all | grep "db-"

# No lingering NVRAM files from old attempts
ls /var/lib/libvirt/qemu/nvram/

# Monitor boot on one node
virsh -c qemu:///system console db-1
```

---

## Risks and notes

- **State replacement**: Destroying and recreating domains means cloud-init runs
  again. VMs come up clean. Any data written to the volumes is preserved (volumes
  are not destroyed in Step 1).

- **NVRAM files**: If old `*_VARS.fd` files remain in `/var/lib/libvirt/qemu/nvram/`
  from the 0.8.3 run, delete them before applying, or the new domain definition
  will conflict with the stale NVRAM state.

  ```bash
  sudo rm -f /var/lib/libvirt/qemu/nvram/db-{1,2,3}_VARS.fd
  ```

- **`loader_readonly` type**: In 0.9.x the field is a string (`"yes"` / `"no"`),
  not a boolean. Using `true` will cause a schema validation error.

- **IDE→virtio XSLT**: Verify this is still needed after upgrading by checking
  the raw domain XML that 0.9.7 generates for an aarch64 guest. If the provider
  now emits virtio for the cloud-init disk natively, the XSLT block can be
  removed entirely.

  ```bash
  virsh -c qemu:///system dumpxml db-1 | grep -A5 "cdrom\|commoninit"
  ```

- **x86_64 path**: The x86_64 default case (`arch = "x86_64"`, no firmware) is
  unaffected by these changes beyond the schema move into `os {}`. Test it after
  the upgrade with a plain `tofu apply` (no `-var arch=...`).
