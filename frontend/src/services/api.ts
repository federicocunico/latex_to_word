import axios from 'axios'

const api = axios.create({
  baseURL: '/api',
  timeout: 600_000, // 10 min – LaTeX compilation can be slow
})

export interface ConversionResponse {
  success: boolean
  docx_download_url: string
  reference_pdf_url: string | null   // LaTeX-compiled reference PDF
  converted_pdf_url: string | null   // DOCX-converted PDF via LibreOffice
  pandoc_log: string
  latex_log: string
}

export function convertZip(
  file: File,
  onProgress?: (percent: number) => void,
): Promise<ConversionResponse> {
  const form = new FormData()
  form.append('file', file)

  return api
    .post<ConversionResponse>('/convert', form, {
      headers: { 'Content-Type': 'multipart/form-data' },
      onUploadProgress(e) {
        if (onProgress && e.total) {
          onProgress(Math.round((e.loaded / e.total) * 100))
        }
      },
    })
    .then((r) => r.data)
}
