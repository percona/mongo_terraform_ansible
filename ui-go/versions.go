package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"regexp"
	"sort"
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

// prefetchVersions warms all image/version caches at startup in a goroutine.
func prefetchVersions() {
	slog.Info("prefetching container image tags and PSMDB versions…")
	getPSMDBVersions()
	getPBMReleases()
	getPMMServerImages()
	getPSMDBImages()
	getPBMImages()
	getPMMClientImages()
	slog.Info("version prefetch complete")
}
