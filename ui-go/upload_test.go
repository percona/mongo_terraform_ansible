package main

import (
	"bytes"
	"encoding/json"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func multipartUploadRequest(t *testing.T, field, filename, content string) *http.Request {
	t.Helper()
	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	part, err := writer.CreateFormFile(field, filename)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := io.WriteString(part, content); err != nil {
		t.Fatal(err)
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	request := httptest.NewRequest(http.MethodPost, "/upload", &body)
	request.Header.Set("Content-Type", writer.FormDataContentType())
	return request
}

func uploadResponse(t *testing.T, recorder *httptest.ResponseRecorder) map[string]string {
	t.Helper()
	if recorder.Code != http.StatusOK {
		t.Fatalf("unexpected status %d: %s", recorder.Code, recorder.Body.String())
	}
	var response map[string]string
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	return response
}

func TestSSHUploadUsesRoleSpecificFilename(t *testing.T) {
	previousDataDir := dataDir
	t.Cleanup(func() { dataDir = previousDataDir })
	dataDir = t.TempDir()

	publicRequest := multipartUploadRequest(t, "ssh_key_file", "workstation.pub", "ssh-ed25519 public")
	publicRequest.SetPathValue("kind", "public")
	publicRecorder := httptest.NewRecorder()
	apiUploadSettingsSSHKeyHandler(publicRecorder, publicRequest)
	publicResponse := uploadResponse(t, publicRecorder)
	if filepath.Base(publicResponse["path"]) != "workstation.pub" {
		t.Fatalf("expected public filename workstation.pub, got %q", publicResponse["path"])
	}

	privateRequest := multipartUploadRequest(t, "ssh_key_file", "workstation", "-----BEGIN OPENSSH PRIVATE KEY-----")
	privateRequest.SetPathValue("kind", "private")
	privateRecorder := httptest.NewRecorder()
	apiUploadSettingsSSHKeyHandler(privateRecorder, privateRequest)
	privateResponse := uploadResponse(t, privateRecorder)
	if filepath.Base(privateResponse["path"]) != "workstation.key" {
		t.Fatalf("expected private filename workstation.key, got %q", privateResponse["path"])
	}

	if _, err := os.Stat(filepath.Join(sshSecretsDir(), "workstation.pub")); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(sshSecretsDir(), "workstation.key")); err != nil {
		t.Fatal(err)
	}
}

func TestChaosTokenUploadUsesUploadedFilename(t *testing.T) {
	previousDataDir := dataDir
	t.Cleanup(func() { dataDir = previousDataDir })
	dataDir = t.TempDir()
	request := multipartUploadRequest(t, "chaos_token_file", "sandbox-token.txt", "token-value")
	recorder := httptest.NewRecorder()
	apiUploadChaosTokenHandler(recorder, request)
	response := uploadResponse(t, recorder)

	if filepath.Base(response["path"]) != "sandbox-token.txt" {
		t.Fatalf("expected token filename sandbox-token.txt, got %q", response["path"])
	}
	data, err := os.ReadFile(filepath.Join(chaosTokenSecretsDir(), "sandbox-token.txt"))
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != "token-value\n" {
		t.Fatalf("unexpected token content %q", data)
	}
}

func TestManagedUploadFilenamePreventsPathTraversal(t *testing.T) {
	if got := managedUploadFilename("../../token.txt", "fallback.token"); got != "token.txt" {
		t.Fatalf("expected basename to be retained safely, got %q", got)
	}
	if got := managedUploadFilename("", "fallback.token"); got != "fallback.token" {
		t.Fatalf("expected fallback filename, got %q", got)
	}
	if got := managedUploadFilename("..", "fallback.token"); got != "fallback.token" {
		t.Fatalf("expected dot-dot filename to use fallback, got %q", got)
	}
	if got := sshUploadFilename("public", "id_ed25519"); got != "id_ed25519.pub" {
		t.Fatalf("expected public extension, got %q", got)
	}
	if got := sshUploadFilename("private", "id_ed25519.pub"); got != "id_ed25519.pub.key" {
		t.Fatalf("expected private extension, got %q", got)
	}
	if got := sshUploadFilename("private", "id_ed25519.pem"); got != "id_ed25519.pem" {
		t.Fatalf("expected existing private extension to be retained, got %q", got)
	}
}
