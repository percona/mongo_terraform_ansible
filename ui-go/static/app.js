// app.js – shared utilities for MongoDB Deploy UI

/**
 * Generic helper to fetch a URL and return parsed JSON response.
 * Handles non-JSON responses gracefully so callers always get a meaningful
 * error message (important for Safari which throws "The string did not match
 * the expected pattern." when JSON.parse fails on non-JSON bodies).
 */
async function apiFetch(url, method = 'GET', body = null) {
  const opts = {
    method,
    headers: { 'Content-Type': 'application/json' },
  };
  if (body !== null) opts.body = JSON.stringify(body);
  const resp = await fetch(url, opts);
  let data;
  try {
    data = await resp.json();
  } catch (_) {
    // Response body is not JSON (e.g. plain-text 404 from a proxy).
    throw new Error(`HTTP ${resp.status}: ${resp.statusText || 'unexpected response'}`);
  }
  if (!resp.ok) throw new Error(data.error || `HTTP ${resp.status}`);
  return data;
}

/**
 * Delete an environment from the index page.
 * @param {string} envId    - The environment ID.
 * @param {string} status   - Current environment status.
 * @param {string} platform - Platform ("docker", "aws", "gcp", "azure").
 */
async function deleteEnvironment(envId, status, platform) {
  // Statuses that imply resources are already gone.
  const alreadyDestroyed = new Set(['deleted', 'destroy_success']);
  const isDestroyed = alreadyDestroyed.has(status);
  const isDocker = platform === 'docker';

  let msg;
  if (isDestroyed) {
    if (isDocker) {
      msg = `Remove environment "${envId}" from the list? Docker containers have already been destroyed.`;
    } else {
      msg = `Remove environment "${envId}" from the list? Cloud resources have already been destroyed.`;
    }
  } else {
    if (isDocker) {
      msg = `⚠️ WARNING: Docker containers for environment "${envId}" may still be running (status: ${status}).\n\nThis will only remove the environment from this UI — it will NOT stop or remove the containers.\n\nAre you sure you want to proceed?`;
    } else {
      msg = `⚠️ WARNING: Cloud resources for environment "${envId}" may still be running (status: ${status}).\n\nThis will only remove the environment from this UI — it will NOT destroy the cloud resources.\n\nAre you sure you want to proceed?`;
    }
  }
  if (!confirm(msg)) return;
  try {
    await apiFetch(`/api/environment/${envId}`, 'DELETE');
    location.reload();
  } catch (err) {
    alert('Error deleting: ' + err.message);
  }
}

/**
 * Purge all environments marked as "Deleted" from the index page.
 */
async function cleanupDeleted() {
  if (!confirm('Remove all destroyed environments from the list? Their cloud resources have already been destroyed.')) return;
  try {
    await apiFetch('/api/environments/deleted', 'DELETE');
    location.reload();
  } catch (err) {
    alert('Error during cleanup: ' + err.message);
  }
}
