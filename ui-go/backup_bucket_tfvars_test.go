package main

import (
	"html/template"
	"os"
	"strings"
	"testing"
)

func TestWriteTfvarsCloudCreateBackupBucket(t *testing.T) {
	dir := t.TempDir()
	origTerraformDir := terraformDir
	terraformDir = dir
	t.Cleanup(func() { terraformDir = origTerraformDir })

	cases := []struct {
		name string
		val  *bool
		want string
	}{
		{"default", nil, "create_backup_bucket = true"},
		{"enabled", boolPtr(true), "create_backup_bucket = true"},
		{"disabled", boolPtr(false), "create_backup_bucket = false"},
	}
	for _, platform := range []string{"aws", "gcp", "azure"} {
		for _, tc := range cases {
			envID := platform + "-bucket-" + tc.name
			cfg := Config{
				CreateBackupBucket: tc.val,
				Clusters:           map[string]ClusterConfig{"cl01": {EnvTag: "test"}},
			}
			if err := writeTfvars(envID, platform, cfg); err != nil {
				t.Fatalf("%s: writeTfvars failed: %v", envID, err)
			}
			content, err := os.ReadFile(tfvarsPath(envID, platform))
			if err != nil {
				t.Fatalf("%s: read tfvars failed: %v", envID, err)
			}
			if !strings.Contains(string(content), tc.want) {
				t.Fatalf("%s: expected %q in tfvars:\n%s", envID, tc.want, content)
			}
		}
	}
}

func TestWriteTfvarsExistingBackupBucket(t *testing.T) {
	dir := t.TempDir()
	origTerraformDir := terraformDir
	terraformDir = dir
	t.Cleanup(func() { terraformDir = origTerraformDir })

	cases := map[string]struct {
		cfg     Config
		want    []string
		notWant []string
	}{
		"aws": {
			cfg: Config{ExistingBucketName: "my-bkp", ExistingBucketRegion: "eu-west-1",
				ExistingBucketAccessKey: "AKIA123", ExistingBucketSecretKey: "s3cr3t", ExistingStorageAccount: "ignored"},
			want: []string{`existing_bucket_name = "my-bkp"`, `existing_bucket_region = "eu-west-1"`,
				`existing_bucket_access_key = "AKIA123"`, `existing_bucket_secret_key = "s3cr3t"`},
			notWant: []string{"existing_storage_account"},
		},
		"gcp": {
			cfg: Config{ExistingBucketName: "my-bkp", ExistingBucketRegion: "ignored",
				ExistingBucketAccessKey: "GOOG123", ExistingBucketSecretKey: "s3cr3t"},
			want:    []string{`existing_bucket_name = "my-bkp"`, `existing_bucket_access_key = "GOOG123"`, `existing_bucket_secret_key = "s3cr3t"`},
			notWant: []string{"existing_bucket_region", "existing_storage_account"},
		},
		"azure": {
			cfg: Config{ExistingBucketName: "backups", ExistingStorageAccount: "myacct",
				ExistingBucketAccessKey: "ignored", ExistingBucketSecretKey: "acctkey=="},
			want:    []string{`existing_bucket_name = "backups"`, `existing_storage_account = "myacct"`, `existing_bucket_secret_key = "acctkey=="`},
			notWant: []string{"existing_bucket_region", "existing_bucket_access_key"},
		},
	}
	for platform, tc := range cases {
		cfg := tc.cfg
		cfg.CreateBackupBucket = boolPtr(false)
		cfg.Clusters = map[string]ClusterConfig{"cl01": {EnvTag: "test"}}
		envID := platform + "-existing-bucket"
		if err := writeTfvars(envID, platform, cfg); err != nil {
			t.Fatalf("%s: writeTfvars failed: %v", platform, err)
		}
		content, err := os.ReadFile(tfvarsPath(envID, platform))
		if err != nil {
			t.Fatalf("%s: read tfvars failed: %v", platform, err)
		}
		tfvars := string(content)
		for _, w := range append(tc.want, "create_backup_bucket = false") {
			if !strings.Contains(tfvars, w) {
				t.Fatalf("%s: expected %q in tfvars:\n%s", platform, w, tfvars)
			}
		}
		for _, nw := range tc.notWant {
			if strings.Contains(tfvars, nw) {
				t.Fatalf("%s: did not expect %q in tfvars:\n%s", platform, nw, tfvars)
			}
		}

		// Existing-bucket settings are ignored when the bucket is created.
		cfg.CreateBackupBucket = boolPtr(true)
		if err := writeTfvars(envID, platform, cfg); err != nil {
			t.Fatalf("%s: writeTfvars failed: %v", platform, err)
		}
		content, _ = os.ReadFile(tfvarsPath(envID, platform))
		if strings.Contains(string(content), "existing_") {
			t.Fatalf("%s: did not expect existing_* vars when creating bucket:\n%s", platform, content)
		}
	}
}

func TestValidateBackupBucketConfig(t *testing.T) {
	off := boolPtr(false)
	cases := []struct {
		name     string
		platform string
		cfg      Config
		wantErr  bool
	}{
		{"create default", "aws", Config{}, false},
		{"no bucket", "aws", Config{CreateBackupBucket: off}, false},
		{"aws complete", "aws", Config{CreateBackupBucket: off, ExistingBucketName: "b", ExistingBucketAccessKey: "a", ExistingBucketSecretKey: "s"}, false},
		{"aws missing secret", "aws", Config{CreateBackupBucket: off, ExistingBucketName: "b", ExistingBucketAccessKey: "a"}, true},
		{"gcp missing access", "gcp", Config{CreateBackupBucket: off, ExistingBucketName: "b", ExistingBucketSecretKey: "s"}, true},
		{"azure complete", "azure", Config{CreateBackupBucket: off, ExistingBucketName: "c", ExistingStorageAccount: "acct", ExistingBucketSecretKey: "k"}, false},
		{"azure missing account", "azure", Config{CreateBackupBucket: off, ExistingBucketName: "c", ExistingBucketSecretKey: "k"}, true},
		{"chaos ignored", "chaos", Config{CreateBackupBucket: off, ExistingBucketName: "b"}, false},
	}
	for _, tc := range cases {
		err := validateBackupBucketConfig(tc.platform, tc.cfg)
		if (err != nil) != tc.wantErr {
			t.Fatalf("%s: err = %v, wantErr %v", tc.name, err, tc.wantErr)
		}
	}
}

func TestWriteTfvarsChaosOmitsCreateBackupBucket(t *testing.T) {
	dir := t.TempDir()
	origTerraformDir := terraformDir
	terraformDir = dir
	t.Cleanup(func() { terraformDir = origTerraformDir })

	cfg := Config{
		CreateBackupBucket: boolPtr(false),
		Clusters:           map[string]ClusterConfig{"cl01": {EnvTag: "test"}},
	}
	if err := writeTfvars("chaos-bucket", "chaos", cfg); err != nil {
		t.Fatalf("writeTfvars failed: %v", err)
	}
	content, err := os.ReadFile(tfvarsPath("chaos-bucket", "chaos"))
	if err != nil {
		t.Fatalf("read tfvars failed: %v", err)
	}
	if strings.Contains(string(content), "create_backup_bucket") {
		t.Fatalf("did not expect create_backup_bucket in CHAOS tfvars:\n%s", content)
	}
}

func TestConfigureTemplateRendersBackupBucketOptions(t *testing.T) {
	tmpl, err := template.New("").Funcs(funcMap).ParseFS(uiAssets, "templates/layout.html", "templates/configure.html")
	if err != nil {
		t.Fatal(err)
	}
	expect := map[string][]string{
		"aws":   {`id="existing_bucket_region"`, `id="existing_bucket_access_key"`, "Secret Access Key"},
		"gcp":   {"HMAC Access ID", "HMAC Secret"},
		"azure": {`id="existing_storage_account"`, "Storage Account Key", "Container Name"},
	}
	for platform, wants := range expect {
		for _, create := range []bool{true, false} {
			cfg := Config{CreateBackupBucket: boolPtr(create), ExistingBucketName: "my-existing-bkp"}
			data := ConfigureData{Platform: platform, Config: cfg, DefaultImages: defaultImages}
			var out strings.Builder
			if err := tmpl.ExecuteTemplate(&out, "layout", data); err != nil {
				t.Fatalf("%s: execute: %v", platform, err)
			}
			page := out.String()
			wants := append([]string{`id="create_backup_bucket"`, `value="my-existing-bkp"`}, wants...)
			for _, want := range wants {
				if !strings.Contains(page, want) {
					t.Errorf("%s (create=%v): expected %q in the rendered page", platform, create, want)
				}
			}
			hidden := `<div id="existing-bucket-body" style="display:none">`
			if create != strings.Contains(page, hidden) {
				t.Errorf("%s (create=%v): unexpected existing-bucket visibility", platform, create)
			}
		}
	}
	data := ConfigureData{Platform: "chaos", Config: Config{}, DefaultImages: defaultImages}
	var out strings.Builder
	if err := tmpl.ExecuteTemplate(&out, "layout", data); err != nil {
		t.Fatalf("chaos: execute: %v", err)
	}
	if strings.Contains(out.String(), `id="create_backup_bucket"`) {
		t.Error("chaos: did not expect create_backup_bucket checkbox")
	}
}
