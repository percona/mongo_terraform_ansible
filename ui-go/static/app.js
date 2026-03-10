// app.js – shared utilities for MongoDB Deploy UI

/**
 * Generic helper to POST JSON and return parsed response.
 */
async function apiFetch(url, method = 'GET', body = null) {
  const opts = {
    method,
    headers: { 'Content-Type': 'application/json' },
  };
  if (body !== null) opts.body = JSON.stringify(body);
  const resp = await fetch(url, opts);
  const data = await resp.json();
  if (!resp.ok) throw new Error(data.error || `HTTP ${resp.status}`);
  return data;
}

/**
 * Delete an environment from the index page.
 * @param {string} envId  - The environment ID.
 * @param {string} status - Current environment status (used to determine if resources are still up).
 */
async function deleteEnvironment(envId, status) {
  // Statuses that imply cloud resources are already gone.
  const alreadyDestroyed = new Set(['deleted', 'destroy_success']);
  const isDestroyed = alreadyDestroyed.has(status);

  let msg;
  if (isDestroyed) {
    msg = `Remove environment "${envId}" from the list? Cloud resources have already been destroyed.`;
  } else {
    msg = `⚠️ WARNING: Cloud resources for environment "${envId}" may still be running (status: ${status}).\n\nThis will only remove the environment from this UI — it will NOT destroy the cloud resources.\n\nAre you sure you want to proceed?`;
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
