<script setup lang="ts">
import { ref } from 'vue'
import { convertZip, type ConversionResponse } from '../services/api'
import ResultsPanel from '../components/ResultsPanel.vue'

type Step = 'idle' | 'uploading' | 'extract' | 'pandoc' | 'latex' | 'libreoffice' | 'done' | 'error'

const dragging = ref(false)
const uploadPercent = ref(0)
const step = ref<Step>('idle')
const result = ref<ConversionResponse | null>(null)
const errorMsg = ref('')

const stepLabels: Record<Step, string> = {
  idle: '',
  uploading: 'Uploading ZIP…',
  extract: 'Extracting archive…',
  pandoc: 'Converting LaTeX → DOCX (Pandoc)…',
  latex: 'Compiling LaTeX → reference PDF…',
  libreoffice: 'Converting DOCX → PDF for preview…',
  done: 'Conversion complete!',
  error: 'Conversion failed',
}

// Backend pipeline steps arrive sequentially; we fake progress based on known order
const pipelineSteps: Step[] = ['extract', 'pandoc', 'latex', 'libreoffice']
let stepInterval: ReturnType<typeof setInterval> | null = null

function startStepProgress() {
  let idx = 0
  step.value = pipelineSteps[0] ?? 'extract'
  stepInterval = setInterval(() => {
    idx = Math.min(idx + 1, pipelineSteps.length - 1)
    step.value = pipelineSteps[idx] ?? 'libreoffice'
  }, 15_000) // rough 15s per step estimate
}

function stopStepProgress() {
  if (stepInterval) clearInterval(stepInterval)
  stepInterval = null
}

async function handleFile(file: File) {
  if (!file.name.endsWith('.zip')) {
    errorMsg.value = 'Please upload a .zip file exported from Overleaf.'
    step.value = 'error'
    return
  }

  result.value = null
  errorMsg.value = ''
  step.value = 'uploading'
  uploadPercent.value = 0

  try {
    const data = await convertZip(file, (p) => {
      uploadPercent.value = p
      if (p === 100) startStepProgress()
    })
    stopStepProgress()
    result.value = data
    step.value = 'done'
  } catch (err: unknown) {
    stopStepProgress()
    step.value = 'error'
    if (err && typeof err === 'object' && 'response' in err) {
      const axiosErr = err as { response?: { data?: { detail?: string } } }
      errorMsg.value = axiosErr.response?.data?.detail ?? 'Unknown error'
    } else if (err instanceof Error) {
      errorMsg.value = err.message
    } else {
      errorMsg.value = 'Unknown error'
    }
  }
}

function onDrop(e: DragEvent) {
  dragging.value = false
  const file = e.dataTransfer?.files?.[0]
  if (file) handleFile(file)
}

function onFileInput(e: Event) {
  const file = (e.target as HTMLInputElement).files?.[0]
  if (file) handleFile(file)
}

function reset() {
  step.value = 'idle'
  result.value = null
  errorMsg.value = ''
  uploadPercent.value = 0
}
</script>

<template>
  <div class="converter">
    <header class="converter__header">
      <h1>Overleaf → DOCX Converter</h1>
      <p>Upload a ZIP exported from Overleaf. Compare the LaTeX PDF with the converted DOCX side by side.</p>
    </header>

    <!-- Upload zone -->
    <div
      v-if="step === 'idle' || step === 'error'"
      class="dropzone"
      :class="{ 'dropzone--dragging': dragging }"
      @dragover.prevent="dragging = true"
      @dragleave="dragging = false"
      @drop.prevent="onDrop"
      @click="($refs.fileInput as HTMLInputElement).click()"
    >
      <input ref="fileInput" type="file" accept=".zip" hidden @change="onFileInput" />
      <div class="dropzone__icon">📦</div>
      <p>Drag &amp; drop your Overleaf ZIP here, or <span class="link">browse</span></p>
      <p class="dropzone__hint">Accepts .zip files up to 200 MB</p>
      <p v-if="step === 'error'" class="error-message">{{ errorMsg }}</p>
    </div>

    <!-- Progress section -->
    <div v-else-if="step !== 'done'" class="progress-section">
      <div class="progress-spinner" />
      <p class="progress-label">{{ stepLabels[step] }}</p>
      <div v-if="step === 'uploading'" class="progress-bar">
        <div class="progress-bar__fill" :style="{ width: `${uploadPercent}%` }" />
      </div>
      <p class="progress-hint">LaTeX compilation may take up to a minute — please wait.</p>
    </div>

    <!-- Results -->
    <div v-else-if="step === 'done' && result">
      <ResultsPanel :result="result" />
      <button class="btn btn--secondary convert-another" @click="reset">Convert another ZIP</button>
    </div>
  </div>
</template>

<style scoped>
.converter {
  max-width: 1600px;
  margin: 0 auto;
  padding: 2rem 1.5rem;
}

.converter__header {
  text-align: center;
  margin-bottom: 2.5rem;
  max-width: 700px;
  margin-left: auto;
  margin-right: auto;
}

.converter__header h1 {
  font-size: 2rem;
  font-weight: 700;
  margin-bottom: 0.5rem;
}

.converter__header p {
  color: #666;
}

.dropzone {
  border: 2px dashed #aaa;
  border-radius: 12px;
  padding: 3rem;
  text-align: center;
  cursor: pointer;
  transition: border-color 0.2s, background 0.2s;
}

.dropzone--dragging,
.dropzone:hover {
  border-color: #2563eb;
  background: #eff6ff;
}

.dropzone__icon {
  font-size: 3rem;
  margin-bottom: 1rem;
}

.link {
  color: #2563eb;
  text-decoration: underline;
  cursor: pointer;
}

.dropzone__hint {
  font-size: 0.85rem;
  color: #999;
  margin-top: 0.5rem;
}

.error-message {
  color: #dc2626;
  margin-top: 1rem;
  font-weight: 500;
}

.progress-section {
  text-align: center;
  padding: 3rem 1rem;
}

.progress-spinner {
  width: 48px;
  height: 48px;
  border: 5px solid #e5e7eb;
  border-top-color: #2563eb;
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
  margin: 0 auto 1.5rem;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}

.progress-label {
  font-size: 1.1rem;
  font-weight: 500;
  margin-bottom: 1rem;
}

.progress-bar {
  height: 8px;
  background: #e5e7eb;
  border-radius: 999px;
  overflow: hidden;
  max-width: 320px;
  margin: 0 auto 1rem;
}

.progress-bar__fill {
  height: 100%;
  background: #2563eb;
  transition: width 0.3s ease;
}

.progress-hint {
  font-size: 0.85rem;
  color: #999;
}

.convert-another {
  display: block;
  margin: 2rem auto 0;
}

.btn {
  padding: 0.6rem 1.6rem;
  border-radius: 8px;
  border: none;
  font-size: 1rem;
  cursor: pointer;
  font-weight: 600;
}

.btn--secondary {
  background: #f3f4f6;
  color: #374151;
}

.btn--secondary:hover {
  background: #e5e7eb;
}
</style>
