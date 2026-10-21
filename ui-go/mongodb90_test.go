package main

import (
	"html/template"
	"net/http"
	"net/http/httptest"
	"os"
	"reflect"
	"strings"
	"testing"
)

func TestMongoDB9VersionParsing(t *testing.T) {
	for _, tc := range []struct {
		version             string
		major, minor, patch int
		hasPatch            bool
	}{
		{"9.0", 9, 0, 0, false},
		{"9.0.2", 9, 0, 2, true},
		{"psmdb-90", 9, 0, 0, false},
		{"percona/percona-server-mongodb:9.0.2-1", 9, 0, 2, true},
		{"psmdb-100", 10, 0, 0, false},
	} {
		t.Run(tc.version, func(t *testing.T) {
			major, minor, patch, hasPatch, ok := parseMongoVersion(tc.version)
			if !ok || major != tc.major || minor != tc.minor || patch != tc.patch || hasPatch != tc.hasPatch {
				t.Fatalf("parsed %q as %d.%d.%d, hasPatch=%v, ok=%v", tc.version, major, minor, patch, hasPatch, ok)
			}
		})
	}
}

func TestClusterSyncRejectsMongoDB9IncludingInheritedRelease(t *testing.T) {
	for _, version := range []string{"9.0", "9.0.2", "psmdb-90", "percona/percona-server-mongodb:9.0.2-1"} {
		if err := validatePCSMMongoVersion(version); err == nil || !strings.Contains(err.Error(), "not a verified") {
			t.Fatalf("expected unverified PCSM line rejection for %s, got %v", version, err)
		}
	}
	cfg := clusterSyncTestConfig()
	cfg.MongoRelease = "psmdb-90"
	cfg.Replsets["source"] = ReplsetConfig{}
	cfg.Replsets["target"] = ReplsetConfig{}
	if err := normalizeAndValidateClusterSync("chaos", &cfg); err == nil {
		t.Fatal("inherited 9.0 release must not bypass ClusterSync validation")
	}
}

func TestPSMDB9RequiresPublishedPackages(t *testing.T) {
	releases := []string{"psmdb-90", "psmdb-83", "psmdb-80"}
	if got := availablePSMDBReleases(releases, nil); !reflect.DeepEqual(got, releases[1:]) {
		t.Fatalf("empty repository exposed: %v", got)
	}
	if got := availablePSMDBReleases(releases, map[string][]string{"psmdb-90": {"9.0.2"}}); !reflect.DeepEqual(got, releases) {
		t.Fatalf("published release hidden: %v", got)
	}
}

func TestMongoDB9SearchAndBackupCompatibility(t *testing.T) {
	for _, platform := range []string{"aws", "gcp", "azure", "chaos"} {
		t.Run(platform, func(t *testing.T) {
			cfg := Config{
				MongoDBDistribution: "community", MongoRelease: "9.0",
				Replsets: map[string]ReplsetConfig{"rs": {EnableMongot: mongotBoolPtr(true), EnablePbm: mongotBoolPtr(false)}},
			}
			if err := normalizeAndValidatePackageConfig(platform, &cfg); err != nil {
				t.Fatal(err)
			}
			if err := validateMongotVersionCompatibility(platform, &cfg); err == nil || !strings.Contains(err.Error(), "not been verified") {
				t.Fatalf("expected inherited MongoDB 9 Search rejection, got %v", err)
			}
			cfg.MongoDBDistribution, cfg.MongoRelease = "psmdb", "psmdb-90"
			cfg.Replsets["rs"] = ReplsetConfig{}
			if err := normalizeAndValidatePackageConfig(platform, &cfg); err == nil {
				t.Fatal("unverified PSMDB 9 PBM combination must be rejected")
			}
			cfg.Replsets["rs"] = ReplsetConfig{EnablePbm: mongotBoolPtr(false)}
			if err := normalizeAndValidatePackageConfig(platform, &cfg); err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestMongoDB9PBMCompatibility(t *testing.T) {
	for _, distribution := range []string{"community", "enterprise", "psmdb"} {
		release := "9.0"
		if distribution == "psmdb" {
			release = "psmdb-90"
		}
		cfg := Config{MongoDBDistribution: distribution, MongoRelease: release, Replsets: map[string]ReplsetConfig{"rs": {}}}
		if err := normalizeAndValidatePackageConfig("chaos", &cfg); err == nil {
			t.Fatalf("unsupported %s 9.0 PBM combination accepted", distribution)
		}
		cfg.Replsets["rs"] = ReplsetConfig{EnablePbm: mongotBoolPtr(false)}
		if err := normalizeAndValidatePackageConfig("chaos", &cfg); err != nil {
			t.Fatal(err)
		}
	}
	if err := validateMongoDB9Backup("replica set", "rs", "8.0", true); err != nil {
		t.Fatal("existing release behavior changed:", err)
	}
	cfg := Config{Replsets: map[string]ReplsetConfig{"rs": {PsmdbImage: "percona/percona-server-mongodb:9.0.2-1"}}}
	if err := normalizeAndValidatePackageConfig("docker", &cfg); err == nil {
		t.Fatal("Docker PBM 9.0 combination accepted")
	}
	cfg.Replsets["rs"] = ReplsetConfig{PsmdbImage: "percona/percona-server-mongodb:9.0.2-1", EnablePbm: mongotBoolPtr(false)}
	if err := normalizeAndValidatePackageConfig("docker", &cfg); err != nil {
		t.Fatal(err)
	}
}

func TestMongoDB9TfvarsForEveryVMProvider(t *testing.T) {
	originalDir := terraformDir
	terraformDir = t.TempDir()
	t.Cleanup(func() { terraformDir = originalDir })
	for _, platform := range []string{"aws", "gcp", "azure", "chaos"} {
		cfg := Config{
			MongoDBDistribution: "community", MongoRelease: "9.0", MongoVersion: "9.0.2",
			Clusters: map[string]ClusterConfig{"cl": {MongoDBDistribution: "enterprise", MongoRelease: "9.0", MongoVersion: "9.0.2"}},
			Replsets: map[string]ReplsetConfig{"rs": {MongoDBDistribution: "community", MongoRelease: "9.0", MongoVersion: "9.0.2"}},
		}
		if err := writeTfvars("mongo90", platform, cfg); err != nil {
			t.Fatal(err)
		}
		content, err := os.ReadFile(tfvarsPath("mongo90", platform))
		if err != nil {
			t.Fatal(err)
		}
		for _, expected := range []string{`mongo_release = "9.0"`, `mongo_version = "9.0.2"`, `mongodb_distribution = "community"`, `mongodb_distribution = "enterprise"`} {
			if !strings.Contains(string(content), expected) {
				t.Fatalf("%s missing %s", platform, expected)
			}
		}
	}
}

func TestOfficialMongoDB9DiscoveryAndTemplate(t *testing.T) {
	cacheMu.Lock()
	originalCache := imgCache
	imgCache = map[string]cacheEntry{}
	cacheMu.Unlock()
	t.Cleanup(func() {
		cacheMu.Lock()
		imgCache = originalCache
		cacheMu.Unlock()
	})
	originalTransport := http.DefaultTransport
	http.DefaultTransport = mongoDB9Transport{t: t}
	t.Cleanup(func() { http.DefaultTransport = originalTransport })
	for _, distribution := range []string{"community", "enterprise"} {
		versions := getOfficialMongoDBVersionsFor(distribution, "Ubuntu 24.04")
		if !reflect.DeepEqual(versions, []string{"9.0"}) {
			t.Fatalf("%s discovered %v, want 9.0 only", distribution, versions)
		}
	}
	tmpl, err := template.New("versions").Funcs(funcMap).Parse(`<script>const OFFICIAL_MONGODB_VERSIONS = {{json .OfficialMongoDBVersions}};</script>`)
	if err != nil {
		t.Fatal(err)
	}
	var output strings.Builder
	if err := tmpl.Execute(&output, ConfigureData{OfficialMongoDBVersions: defaultMongoDBOfficialVersions}); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(output.String(), `"9.0"`) {
		t.Fatalf("official version data missing from template: %s", output.String())
	}
}

type mongoDB9Transport struct{ t *testing.T }

func (transport mongoDB9Transport) RoundTrip(request *http.Request) (*http.Response, error) {
	if request.URL.Host != "repo.mongodb.org" && request.URL.Host != "repo.mongodb.com" {
		transport.t.Fatalf("unexpected repository host: %s", request.URL)
	}
	response := httptest.NewRecorder()
	if strings.Contains(request.URL.Path, "/9.0/") && strings.HasSuffix(request.URL.Path, "/Packages") {
		packageName := "mongodb-org-server"
		if request.URL.Host == "repo.mongodb.com" {
			packageName = "mongodb-enterprise-server"
		}
		response.WriteString("Package: " + packageName + "\nVersion: 9.0.2\n\n")
	} else {
		response.WriteHeader(http.StatusNotFound)
	}
	return response.Result(), nil
}
