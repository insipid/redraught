(function () {
  const appEl = document.getElementById('app');
  if (!appEl) return;

  const sessionId = appEl.dataset.sessionId;
  const stepCount = parseInt(appEl.dataset.stepCount, 10);
  let currentStep = 1;

  const inputContent  = document.getElementById('input-content');
  const outputEditor  = document.getElementById('output-editor');
  const diffContent   = document.getElementById('diff-content');
  const promptEditor  = document.getElementById('prompt-editor');
  const commandEditor = document.getElementById('command-editor');
  const runStepBtn    = document.getElementById('run-step-btn');
  const runAllBtn     = document.getElementById('run-all-btn');
  const saveOutputBtn = document.getElementById('save-output-btn');
  const stepIndicator = document.getElementById('step-indicator');
  const stderrOutput  = document.getElementById('stderr-output');

  function updateDiff() {
    const left  = inputContent.textContent || '';
    const right = outputEditor.value || '';
    if (!left && !right) { diffContent.innerHTML = ''; return; }
    const patch = Diff.createPatch('document', left, right, '', '');
    diffContent.innerHTML = Diff2Html.html(patch, {
      drawFileList: false,
      matching: 'lines',
      outputFormat: 'line-by-line'
    });
  }

  outputEditor.addEventListener('input', updateDiff);

  async function loadStep(n) {
    currentStep = n;
    stepIndicator.textContent = `Step ${n} of ${stepCount}`;

    const resp = await fetch(`/sessions/${sessionId}/steps/${n}`);
    const data = await resp.json();

    inputContent.textContent = data.input  || '';
    outputEditor.value       = data.output || '';
    promptEditor.value       = data.prompt  || '';
    commandEditor.value      = data.command || '';
    stderrOutput.textContent = '';

    updateDiff();

    document.querySelectorAll('.step-item').forEach(el => {
      el.classList.toggle('active', parseInt(el.dataset.n, 10) === n);
    });
  }

  runStepBtn.addEventListener('click', async () => {
    runStepBtn.disabled    = true;
    runStepBtn.textContent = 'Running…';

    const resp = await fetch(`/sessions/${sessionId}/steps/${currentStep}/run`, {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify({ command: commandEditor.value })
    });
    const data = await resp.json();

    runStepBtn.disabled    = false;
    runStepBtn.textContent = 'Run Step';
    stderrOutput.textContent = data.stderr || '';

    if (data.success) {
      outputEditor.value = data.output || '';
      updateDiff();
      setBadge(currentStep, 'done');
    } else {
      stderrOutput.textContent = `Failed (exit ${data.exit_code})\n${data.stderr}`;
    }
  });

  saveOutputBtn.addEventListener('click', async () => {
    await fetch(`/sessions/${sessionId}/steps/${currentStep}`, {
      method:  'PUT',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify({ content: outputEditor.value })
    });
    setBadge(currentStep, 'done');
  });

  runAllBtn.addEventListener('click', async () => {
    runAllBtn.disabled    = true;
    runAllBtn.textContent = 'Running…';

    const resp    = await fetch(`/sessions/${sessionId}/run-all`, { method: 'POST' });
    const results = await resp.json();

    runAllBtn.disabled    = false;
    runAllBtn.textContent = 'Run All';

    results.forEach(r => setBadge(r.n, r.success ? 'done' : 'error'));
    if (results.length > 0) loadStep(results[results.length - 1].n);
  });

  document.querySelectorAll('.step-item').forEach(el => {
    el.addEventListener('click', () => loadStep(parseInt(el.dataset.n, 10)));
  });

  function setBadge(n, status) {
    const el = document.querySelector(`[data-status-n="${n}"]`);
    if (!el) return;
    el.textContent = status;
    el.className   = `step-badge status-${status}`;
  }

  loadStep(1);
})();
