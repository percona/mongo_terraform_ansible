package main

import (
	"compress/gzip"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

func getDockerHubTags(namespace, repo string, limit int) []string {
	key := "dh:" + namespace + "/" + repo
	if v, ok := cacheGet(key); ok {
		return v.([]string)
	}
	url := fmt.Sprintf("https://hub.docker.com/v2/repositories/%s/%s/tags/?page_size=%d&ordering=last_updated", namespace, repo, limit)
	client := &http.Client{Timeout: 8 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		slog.Warn("docker hub tags fetch failed", "repo", namespace+"/"+repo, "err", err)
		cacheSet(key, []string{})
		return []string{}
	}
	defer resp.Body.Close()
	var result struct {
		Results []struct {
			Name string `json:"name"`
		} `json:"results"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		slog.Warn("docker hub tags decode failed", "repo", namespace+"/"+repo, "err", err)
		cacheSet(key, []string{})
		return []string{}
	}
	tags := make([]string, 0, len(result.Results))
	for _, r := range result.Results {
		tags = append(tags, r.Name)
	}
	slog.Info("fetched docker hub tags", "repo", namespace+"/"+repo, "count", len(tags))
	cacheSet(key, tags)
	return tags
}

// fetchPerconaRepoPage fetches the Percona repository listing page and returns
// its body text. The result is cached to avoid redundant HTTP requests.
func fetchPerconaRepoPage() string {
	const key = "percona_repo_page"
	if v, ok := cacheGet(key); ok {
		return v.(string)
	}
	client := &http.Client{Timeout: 8 * time.Second}
	resp, err := client.Get("https://repo.percona.com/")
	if err != nil {
		slog.Warn("percona repo page fetch failed", "err", err)
		cacheSet(key, "")
		return ""
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		slog.Warn("percona repo page non-200", "status", resp.StatusCode)
		cacheSet(key, "")
		return ""
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		slog.Warn("percona repo page read failed", "err", err)
		cacheSet(key, "")
		return ""
	}
	page := string(body)
	cacheSet(key, page)
	return page
}

func getPSMDBVersions() []string {
	const key = "psmdb_versions"
	if v, ok := cacheGet(key); ok {
		return v.([]string)
	}
	var versions []string
	page := fetchPerconaRepoPage()
	if page != "" {
		re := regexp.MustCompile(`psmdb-\d+`)
		found := re.FindAllString(page, -1)
		seen := map[string]bool{}
		for _, v := range found {
			if !seen[v] {
				seen[v] = true
				versions = append(versions, v)
			}
		}
		// Sort descending
		sort.Slice(versions, func(i, j int) bool { return versions[i] > versions[j] })
		slog.Info("fetched PSMDB versions", "count", len(versions))
	} else {
		slog.Warn("psmdb versions fetch failed – using defaults")
	}
	if len(versions) == 0 {
		versions = defaultPSMDBVersions
	}
	cacheSet(key, versions)
	return versions
}

// getPBMVersions returns a flat, sorted-descending list of all available
// percona-backup-mongodb package versions from the Percona "pbm" APT repository.
// PBM uses a single repository (no per-major-version repos), so there is no
// "release" concept for PBM — all versions live together in one place.
func getPBMVersions() []string {
	const key = "pbm_all_versions"
	if v, ok := cacheGet(key); ok {
		return v.([]string)
	}
	versions := fetchPerconaAPTPackageVersions("pbm", "percona-backup-mongodb")
	if len(versions) == 0 {
		slog.Warn("PBM versions fetch failed – using Docker Hub fallback")
		versions = pbmVersionsFromDockerHub()
	}
	cacheSet(key, versions)
	return versions
}

// pbmVersionsFromDockerHub derives a flat sorted-descending list of PBM versions
// from Docker Hub tags, used when the Percona APT repository is unreachable.
func pbmVersionsFromDockerHub() []string {
	tags := getDockerHubTags("percona", "percona-backup-mongodb", 100)
	re := regexp.MustCompile(`^(\d+\.\d+\.\d+)$`)
	seen := map[string]bool{}
	var versions []string
	for _, tag := range tags {
		if re.MatchString(tag) && !seen[tag] {
			seen[tag] = true
			versions = append(versions, tag)
		}
	}
	sort.Slice(versions, func(i, j int) bool { return semverGreater(versions[i], versions[j]) })
	return versions
}

func getPMMServerImages() []string {
	tags := getDockerHubTags("percona", "pmm-server", 30)
	if len(tags) == 0 {
		return []string{"latest"}
	}
	return tags
}

func getPSMDBImages() []string {
	tags := getDockerHubTags("percona", "percona-server-mongodb", 30)
	if len(tags) == 0 {
		return []string{"latest"}
	}
	return tags
}

func getPBMImages() []string {
	tags := getDockerHubTags("percona", "percona-backup-mongodb", 20)
	if len(tags) == 0 {
		return []string{"latest"}
	}
	return tags
}

func getPMMClientImages() []string {
	tags := getDockerHubTags("percona", "pmm-client", 20)
	if len(tags) == 0 {
		return []string{"latest"}
	}
	return tags
}

// semverGreater returns true if version string a is semantically greater than b.
// Versions are dot-separated numeric components (e.g., "7.0.12" vs "7.0.9").
// Lexicographic comparison fails for multi-digit patch numbers ("7.0.9" > "7.0.10"
// lexicographically but "7.0.10" is newer semantically).
func semverGreater(a, b string) bool {
	ap := strings.Split(a, ".")
	bp := strings.Split(b, ".")
	n := len(ap)
	if len(bp) > n {
		n = len(bp)
	}
	for i := 0; i < n; i++ {
		var ai, bi int
		if i < len(ap) {
			ai, _ = strconv.Atoi(ap[i])
		}
		if i < len(bp) {
			bi, _ = strconv.Atoi(bp[i])
		}
		if ai != bi {
			return ai > bi
		}
	}
	return false
}

// fetchPerconaAPTPackageVersions queries the Percona APT repository Packages index
// for repoName (e.g., "psmdb-70", "pbm") and returns a sorted-descending list of
// upstream version strings (e.g., ["7.0.12", "7.0.11"]) for the given packageName.
// It tries the gzip-compressed index first, then the plain-text index.
// The distro "jammy" (Ubuntu 22.04 LTS) is used because Percona supports it well
// and its version strings match those in other distributions.
func fetchPerconaAPTPackageVersions(repoName, packageName string) []string {
	cacheKey := "percona_apt:" + repoName + ":" + packageName
	if v, ok := cacheGet(cacheKey); ok {
		return v.([]string)
	}

	baseURL := "https://repo.percona.com/" + repoName + "/apt/dists/jammy/main/binary-amd64/"
	versions := readAPTPackages(baseURL+"Packages.gz", true, packageName)
	if len(versions) == 0 {
		versions = readAPTPackages(baseURL+"Packages", false, packageName)
	}

	slog.Info("fetched Percona APT package versions", "repo", repoName, "package", packageName, "count", len(versions))
	cacheSet(cacheKey, versions)
	return versions
}

// readAPTPackages fetches a Debian Packages (or Packages.gz) file and returns
// the sorted-descending upstream version list for the named package.
func readAPTPackages(url string, gzipped bool, packageName string) []string {
	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		slog.Warn("APT Packages fetch failed", "url", url, "err", err)
		return nil
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil
	}

	var reader io.Reader = resp.Body
	if gzipped {
		gz, err := gzip.NewReader(resp.Body)
		if err != nil {
			slog.Warn("APT Packages gzip open failed", "url", url, "err", err)
			return nil
		}
		defer gz.Close()
		reader = gz
	}

	body, err := io.ReadAll(reader)
	if err != nil {
		slog.Warn("APT Packages read failed", "url", url, "err", err)
		return nil
	}

	return parseAPTPackageVersions(string(body), packageName)
}

// parseAPTPackageVersions parses a Debian Packages file and extracts unique
// upstream version strings for the given package name.
// A typical version field is "7.0.12-3.jammy"; this function strips the
// Debian revision suffix ("-3.jammy") and returns "7.0.12".
func parseAPTPackageVersions(content, packageName string) []string {
	seen := map[string]bool{}
	var versions []string

	var currentPackage string
	for _, line := range strings.Split(content, "\n") {
		switch {
		case strings.HasPrefix(line, "Package: "):
			currentPackage = strings.TrimPrefix(line, "Package: ")
		case strings.HasPrefix(line, "Version: ") && currentPackage == packageName:
			fullVer := strings.TrimPrefix(line, "Version: ")
			// Strip Debian revision suffix: "7.0.12-3.jammy" → "7.0.12"
			upstream := strings.SplitN(fullVer, "-", 2)[0]
			if upstream != "" && !seen[upstream] {
				seen[upstream] = true
				versions = append(versions, upstream)
			}
		}
	}

	sort.Slice(versions, func(i, j int) bool { return semverGreater(versions[i], versions[j]) })
	return versions
}

// getPSMDBMinorVersionsByMajor returns a map from major release key (e.g. "psmdb-70")
// to a sorted-descending list of specific minor versions (e.g. ["7.0.12", "7.0.11"]).
// Versions are pulled from the Percona APT repository index for each major release.
// Falls back to Docker Hub image tags if the APT repo is unreachable.
func getPSMDBMinorVersionsByMajor() map[string][]string {
	const key = "psmdb_minor_by_major"
	if v, ok := cacheGet(key); ok {
		return v.(map[string][]string)
	}

	result := map[string][]string{}
	for _, release := range getPSMDBVersions() {
		versions := fetchPerconaAPTPackageVersions(release, "percona-server-mongodb")
		if len(versions) > 0 {
			result[release] = versions
		}
	}

	// Fall back to Docker Hub tags when the Percona repo is unreachable.
	if len(result) == 0 {
		result = psmdbMinorVersionsFromDockerHub()
	}

	cacheSet(key, result)
	return result
}

// psmdbMinorVersionsFromDockerHub derives PSMDB minor versions from Docker Hub image tags.
// Used as a fallback when the Percona APT repository is unreachable.
func psmdbMinorVersionsFromDockerHub() map[string][]string {
	result := map[string][]string{}
	tags := getDockerHubTags("percona", "percona-server-mongodb", 200)
	re := regexp.MustCompile(`^(\d+\.\d+)\.(\d+)`)
	seen := map[string]map[string]bool{}
	for _, tag := range tags {
		m := re.FindStringSubmatch(tag)
		if m == nil {
			continue
		}
		majorMinor := m[1]
		version := majorMinor + "." + m[2]
		parts := strings.SplitN(majorMinor, ".", 2)
		if len(parts) != 2 {
			continue
		}
		releaseKey := "psmdb-" + parts[0] + parts[1]
		if seen[releaseKey] == nil {
			seen[releaseKey] = map[string]bool{}
		}
		if !seen[releaseKey][version] {
			seen[releaseKey][version] = true
			result[releaseKey] = append(result[releaseKey], version)
		}
	}
	for k := range result {
		sort.Slice(result[k], func(i, j int) bool { return semverGreater(result[k][i], result[k][j]) })
	}
	return result
}

// prefetchVersions warms all image/version caches at startup in a goroutine.
func prefetchVersions() {
	slog.Info("prefetching container image tags and PSMDB versions…")
	getPSMDBVersions()
	getPBMVersions()
	getPMMServerImages()
	getPSMDBImages()
	getPBMImages()
	getPMMClientImages()
	getPSMDBMinorVersionsByMajor()
	slog.Info("version prefetch complete")
}

// ─── Cached-only getters ─────────────────────────────────────────────────────
// These variants return whatever is currently in cache (or safe defaults) without
// making any outbound HTTP requests. They are used to render the configure page
// immediately; the browser then refreshes the version dropdowns asynchronously
// via /api/versions once the page has loaded.

func cachedPSMDBVersions() []string {
	if v, ok := cacheGet("psmdb_versions"); ok {
		return v.([]string)
	}
	return defaultPSMDBVersions
}

func cachedPBMVersions() []string {
	if v, ok := cacheGet("pbm_all_versions"); ok {
		return v.([]string)
	}
	return []string{}
}

func cachedPMMServerImages() []string {
	if v, ok := cacheGet("dh:percona/pmm-server"); ok {
		return v.([]string)
	}
	return []string{"latest"}
}

func cachedPSMDBImages() []string {
	if v, ok := cacheGet("dh:percona/percona-server-mongodb"); ok {
		return v.([]string)
	}
	return []string{"latest"}
}

func cachedPBMImages() []string {
	if v, ok := cacheGet("dh:percona/percona-backup-mongodb"); ok {
		return v.([]string)
	}
	return []string{"latest"}
}

func cachedPMMClientImages() []string {
	if v, ok := cacheGet("dh:percona/pmm-client"); ok {
		return v.([]string)
	}
	return []string{"latest"}
}

func cachedPSMDBMinorVersionsByMajor() map[string][]string {
	if v, ok := cacheGet("psmdb_minor_by_major"); ok {
		return v.(map[string][]string)
	}
	return map[string][]string{}
}
