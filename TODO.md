I want a overleaf project to Microsoft Word (DOCX) converter.
My idea is the following:
I upload to a webpage the ZIP (downloaded as source) of overleaf. Then I unpack, and use pandoc (https://pandoc.org/ see releases at https://github.com/jgm/pandoc/releases/latest according to current OS, at build time of container, include it) and create the Docx file.

To find main file, look for one named main.tex.

I want to be sure the process goes fine, so as check, include also latex compiler and compile zip to pdf, then convert the pandoc's docx to pdf and do a similarity check, importantly matching the layout not only the content, for instance, using a combined text+images similarity check (SSIM?). Ensure images are embedded fine and also all the content, produce a similarity score based on all pages individually and a global score.

Create an UI for doing so in VUE3 (see frontend/ for blank project) and a backend to launch command line and check everything works in FASTAPI.

