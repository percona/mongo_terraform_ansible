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
  if (!confirm(`Delete environment "${envId}"? This only removes the UI record, not cloud resources.`)) return;
  try {
    await apiFetch(`/api/environment/${envId}`, 'DELETE');
    const card = document.getElementById(`env-${envId}`);
    if (card) card.remove();
  } catch (err) {
    alert('Error deleting: ' + err.message);
  }
}
