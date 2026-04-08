<script setup lang="ts">
import { ref } from 'vue'
import type { ConversionResponse } from '../services/api'

const props = defineProps<{ result: ConversionResponse }>()

const showPandocLog = ref(false)
const showLatexLog = ref(false)
</script>

<template>
  <div class="results">
    <!-- Action bar -->
    <div class="actions-bar">
      <a :href="result.docx_download_url" class="btn btn--primary" download>
        ⬇ Download DOCX
      </a>
    </div>

    <!-- Side-by-side PDF comparison -->
    <div class="pdf-comparison">
      <!-- Reference: LaTeX PDF -->
      <div class="pdf-pane">
        <div class="pdf-pane__label">LaTeX PDF (reference)</div>
        <div v-if="result.reference_pdf_url" class="pdf-pane__viewer">
          <iframe
            :src="result.reference_pdf_url"
            class="pdf-frame"
            type="application/pdf"
            title="LaTeX reference PDF"
          />
        </div>
        <div v-else class="pdf-pane__unavailable">
          LaTeX compilation did not produce a PDF.<br />
          Check the LaTeX log below for errors.
        </div>
      </div>

      <!-- Converted: DOCX → PDF -->
      <div class="pdf-pane">
        <div class="pdf-pane__label">DOCX → PDF (converted)</div>
        <div v-if="result.converted_pdf_url" class="pdf-pane__viewer">
          <iframe
            :src="result.converted_pdf_url"
            class="pdf-frame"
            type="application/pdf"
            title="Converted DOCX as PDF"
          />
        </div>
        <div v-else class="pdf-pane__unavailable">
          PDF preview unavailable.<br />
          Download the DOCX to view it in Word.
        </div>
      </div>
    </div>

    <!-- Logs -->
    <div class="logs">
      <button class="log-toggle" @click="showPandocLog = !showPandocLog">
        {{ showPandocLog ? '▲' : '▶' }} Pandoc Log
      </button>
      <pre v-if="showPandocLog" class="log-body">{{ result.pandoc_log || '(no output)' }}</pre>

      <button class="log-toggle" @click="showLatexLog = !showLatexLog">
        {{ showLatexLog ? '▲' : '▶' }} LaTeX Compilation Log
      </button>
      <pre v-if="showLatexLog" class="log-body">{{ result.latex_log || '(no output)' }}</pre>
    </div>
  </div>
</template>

<style scoped>
.results {
  animation: fadein 0.3s ease;
}

@keyframes fadein {
  from { opacity: 0; transform: translateY(8px); }
  to { opacity: 1; transform: none; }
}

.actions-bar {
  display: flex;
  align-items: center;
  gap: 1.5rem;
  margin-bottom: 1.5rem;
  padding-bottom: 1rem;
  border-bottom: 1px solid #e5e7eb;
}

.btn {
  display: inline-block;
  padding: 0.65rem 1.8rem;
  border-radius: 8px;
  font-size: 1rem;
  font-weight: 600;
  cursor: pointer;
  text-decoration: none;
  border: none;
}

.btn--primary {
  background: #2563eb;
  color: white;
}

.btn--primary:hover {
  background: #1d4ed8;
}

/* Side-by-side layout */
.pdf-comparison {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 1.25rem;
  margin-bottom: 2rem;
}

.pdf-pane {
  display: flex;
  flex-direction: column;
  border: 1px solid #e5e7eb;
  border-radius: 10px;
  overflow: hidden;
}

.pdf-pane__label {
  background: #f3f4f6;
  border-bottom: 1px solid #e5e7eb;
  padding: 0.6rem 1rem;
  font-size: 0.85rem;
  font-weight: 600;
  color: #374151;
  text-align: center;
}

.pdf-pane__viewer {
  flex: 1;
}

.pdf-frame {
  width: 100%;
  height: 82vh;
  min-height: 500px;
  border: none;
  display: block;
}

.pdf-pane__unavailable {
  padding: 3rem 1rem;
  text-align: center;
  color: #9ca3af;
  font-size: 0.9rem;
  line-height: 1.6;
}

/* Logs */
.logs {
  margin-top: 0.5rem;
}

.log-toggle {
  background: none;
  border: none;
  font-size: 0.9rem;
  font-weight: 600;
  color: #374151;
  cursor: pointer;
  padding: 0.4rem 0;
  display: block;
  margin-bottom: 0.25rem;
}

.log-toggle:hover {
  color: #2563eb;
}

.log-body {
  background: #1e1e1e;
  color: #d4d4d4;
  border-radius: 8px;
  padding: 1rem;
  font-size: 0.78rem;
  overflow-x: auto;
  white-space: pre-wrap;
  max-height: 300px;
  overflow-y: auto;
  margin-bottom: 1rem;
}
</style>
