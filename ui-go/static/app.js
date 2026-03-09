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
 */
async function deleteEnvironment(envId) {
  if (!confirm(`Remove environment "${envId}" from the list? Cloud resources have already been destroyed.`)) return;
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
