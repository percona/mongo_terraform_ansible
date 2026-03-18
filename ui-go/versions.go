package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"regexp"
	"sort"
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
// its body text. The result is cached to avoid redundant HTTP requests since
// both getPSMDBVersions and getPBMReleases need it.
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

func getPBMReleases() []string {
	const key = "pbm_releases"
	if v, ok := cacheGet(key); ok {
		return v.([]string)
	}
	var releases []string
	page := fetchPerconaRepoPage()
	if page != "" {
		re := regexp.MustCompile(`pbm-\d+`)
		found := re.FindAllString(page, -1)
		seen := map[string]bool{}
		for _, v := range found {
			if !seen[v] {
				seen[v] = true
				releases = append(releases, v)
			}
		}
		sort.Slice(releases, func(i, j int) bool { return releases[i] > releases[j] })
		slog.Info("fetched PBM releases", "count", len(releases))
	} else {
		slog.Warn("pbm releases fetch failed – using defaults")
	}
	if len(releases) == 0 {
		releases = defaultPBMReleases
	}
	cacheSet(key, releases)
	return releases
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

// getPSMDBMinorVersionsByMajor returns a map from major release (e.g. "psmdb-70") to
// a slice of specific minor versions (e.g. ["7.0.12", "7.0.11", "7.0.10"]).
// Versions are derived from the percona/percona-server-mongodb Docker Hub tags which
// use the same version numbering as the Percona apt/yum repositories.
func getPSMDBMinorVersionsByMajor() map[string][]string {
	const key = "psmdb_minor_by_major"
	if v, ok := cacheGet(key); ok {
		return v.(map[string][]string)
	}
	result := map[string][]string{}
	// Fetch up to 200 tags to cover all major versions.
	tags := getDockerHubTags("percona", "percona-server-mongodb", 200)
	// Pattern: e.g. "7.0.12-1-multi" or "7.0.12" – capture major and full version.
	re := regexp.MustCompile(`^(\d+\.\d+)\.(\d+)`)
	seen := map[string]map[string]bool{}
	for _, tag := range tags {
		m := re.FindStringSubmatch(tag)
		if m == nil {
			continue
		}
		majorMinor := m[1]               // e.g. "7.0"
		version := majorMinor + "." + m[2] // e.g. "7.0.12"
		// Map major.minor to psmdb release key: "7.0" → "psmdb-70", "8.0" → "psmdb-80"
		parts := strings.SplitN(majorMinor, ".", 2)
		if len(parts) != 2 {
			continue
		}
		releaseKey := "psmdb-" + parts[0] + parts[1] // "psmdb-70"
		if seen[releaseKey] == nil {
			seen[releaseKey] = map[string]bool{}
		}
		if !seen[releaseKey][version] {
			seen[releaseKey][version] = true
			result[releaseKey] = append(result[releaseKey], version)
		}
	}
	// Sort each list descending.
	for k := range result {
		sort.Slice(result[k], func(i, j int) bool { return result[k][i] > result[k][j] })
	}
	cacheSet(key, result)
	return result
}

// getPBMMinorVersionsByMajor returns a map from major release (e.g. "pbm-20") to
// a slice of specific minor versions (e.g. ["2.7.0", "2.6.0"]).
func getPBMMinorVersionsByMajor() map[string][]string {
	const key = "pbm_minor_by_major"
	if v, ok := cacheGet(key); ok {
		return v.(map[string][]string)
	}
	result := map[string][]string{}
	tags := getDockerHubTags("percona", "percona-backup-mongodb", 100)
	re := regexp.MustCompile(`^(\d+)\.(\d+)\.(\d+)`)
	seen := map[string]map[string]bool{}
	for _, tag := range tags {
		m := re.FindStringSubmatch(tag)
		if m == nil {
			continue
		}
		major := m[1]
		version := major + "." + m[2] + "." + m[3]
		releaseKey := "pbm-" + major + m[2] // e.g. "pbm-27" for 2.7.x
		if seen[releaseKey] == nil {
			seen[releaseKey] = map[string]bool{}
		}
		if !seen[releaseKey][version] {
			seen[releaseKey][version] = true
			result[releaseKey] = append(result[releaseKey], version)
		}
	}
	for k := range result {
		sort.Slice(result[k], func(i, j int) bool { return result[k][i] > result[k][j] })
	}
	cacheSet(key, result)
	return result
}

// prefetchVersions warms all image/version caches at startup in a goroutine.
func prefetchVersions() {
	slog.Info("prefetching container image tags and PSMDB versions…")
	getPSMDBVersions()
	getPBMReleases()
	getPMMServerImages()
	getPSMDBImages()
	getPBMImages()
	getPMMClientImages()
	getPSMDBMinorVersionsByMajor()
	getPBMMinorVersionsByMajor()
	slog.Info("version prefetch complete")
}
