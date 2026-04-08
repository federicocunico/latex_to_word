from dataclasses import dataclass


@dataclass
class ConversionResult:
    docx_path: str
    reference_pdf_path: str   # path to LaTeX-compiled PDF; may be "" if compilation failed
    converted_pdf_path: str   # path to DOCX-converted PDF; may be "" if LibreOffice failed
    pandoc_log: str
    latex_log: str
    success: bool
    error_message: str = ""
