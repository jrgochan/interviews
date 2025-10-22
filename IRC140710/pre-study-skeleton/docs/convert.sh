#!/usr/bin/env bash
# Convert Jason Gochanour CV from Markdown to PDF (Pandoc + LaTeX), with safe quoting, modern flags,
# auto-install of needed TeX packages (tlmgr), and graceful fallbacks.
# Usage: ./convert.sh [output_filename.pdf] [-v|--verbose] [-h|--help]

set -uo pipefail

# -----------------------------
# Configuration
# -----------------------------
INPUT_FILE="Jason-Gochanour-CV-IRC140710.md"
DEFAULT_OUTPUT="Jason-Gochanour-CV-IRC140710.pdf"
OUTPUT_FILE=""
VERBOSE=false

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# Engines to try (best → ok → fallback)
ENGINES=("lualatex" "xelatex" "pdflatex")

# Packages we rely on (header & nicer fonts/spacing/colors)
REQUIRED_PKGS_COMMON=( "xcolor" "enumitem" "microtype" )
REQUIRED_PKGS_XELUA=( "fontspec" )
REQUIRED_PKGS_PDFLATEX=( "latex-bin" "latex" "base" ) # placeholders for core; see below
RECOMMENDED_FORMATTING_PKGS=( "titlesec" )
# For lualatex missing dep reported in your logs:
REQUIRED_PKGS_LUALATEX=( "lualatex-math" )

# -----------------------------
# CLI Args
# -----------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--verbose) VERBOSE=true; shift;;
    -h|--help)
      echo "Usage: $0 [output_filename.pdf] [-v|--verbose] [-h|--help]"
      echo "  output_filename.pdf: Custom output filename (default: $DEFAULT_OUTPUT)"
      exit 0;;
    *)  if [[ -z "$OUTPUT_FILE" ]]; then OUTPUT_FILE="$1"; else
          echo -e "${RED}Error: Unknown argument '$1'${NC}"; exit 1; fi; shift;;
  esac
done

[[ -z "$OUTPUT_FILE" ]] && OUTPUT_FILE="$DEFAULT_OUTPUT"

echo -e "${BLUE}=== CV Markdown to PDF Converter ===${NC}"
echo -e "Input:  ${INPUT_FILE}"
echo -e "Output: ${OUTPUT_FILE}"
echo

# -----------------------------
# Preflight
# -----------------------------
if [[ ! -f "$INPUT_FILE" ]]; then
  echo -e "${RED}Error: Input file '$INPUT_FILE' not found!${NC}"; exit 1
fi

if ! command -v pandoc >/dev/null 2>&1; then
  echo -e "${RED}Error: pandoc is not installed!${NC}"
  echo -e "${YELLOW}Install:${NC} brew install pandoc   (macOS)"
  exit 1
fi

check_latex() {
  local latex_paths=(
    "/usr/local/texlive/*/bin/universal-darwin"
    "/usr/local/texlive/*/bin/x86_64-darwin"
    "/usr/local/texlive/*/bin/*-linux"
    "/Library/TeX/texbin" "/usr/bin" "/usr/local/bin"
  )
  if command -v pdflatex >/dev/null 2>&1 || command -v xelatex >/dev/null 2>&1 || command -v lualatex >/dev/null 2>&1; then
    return 0
  fi
  for pattern in "${latex_paths[@]}"; do
    for path in $pattern; do
      if [[ -d "$path" ]] && { [[ -x "$path/pdflatex" ]] || [[ -x "$path/xelatex" ]] || [[ -x "$path/lualatex" ]]; }; then
        export PATH="$path:$PATH"
        $VERBOSE && echo -e "${GREEN}Found LaTeX in: $path${NC}"
        return 0
      fi
    done
  done
  return 1
}

echo -e "${BLUE}Checking for LaTeX installation...${NC}"
if check_latex; then
  echo -e "${GREEN}✅ LaTeX found${NC}"
  LATEX_AVAILABLE=true
else
  echo -e "${YELLOW}⚠️ LaTeX not found in common locations${NC}"
  LATEX_AVAILABLE=false
fi

# -----------------------------
# Package helpers (tlmgr)
# -----------------------------
has_pkg() {  # kpsewhich returns a path if the sty is installed
  kpsewhich "$1" >/dev/null 2>&1
}

install_pkgs_tlmgr() {
  # Takes a list of TeX Live package names; installs the ones missing.
  # Requires sudo on BasicTeX/MacTeX.
  if ! command -v tlmgr >/dev/null 2>&1; then
    $VERBOSE && echo -e "${YELLOW}tlmgr not found; cannot auto-install TeX packages.${NC}"
    return 1
  fi

  echo -e "${BLUE}Ensuring TeX Live is up to date (tlmgr)...${NC}"
  if ! sudo tlmgr update --self >/dev/null 2>&1; then
    echo -e "${YELLOW}Could not update tlmgr (you can ignore if offline).${NC}"
  fi

  local to_install=()
  for pkg in "$@"; do
    # For common LaTeX packages, kpsewhich tests by .sty name; tlmgr names match the package (titlesec, xcolor, etc)
    case "$pkg" in
      titlesec) ! has_pkg "titlesec.sty" && to_install+=("titlesec");;
      xcolor)   ! has_pkg "xcolor.sty"   && to_install+=("xcolor");;
      enumitem) ! has_pkg "enumitem.sty" && to_install+=("enumitem");;
      microtype)! has_pkg "microtype.sty"&& to_install+=("microtype");;
      fontspec) ! has_pkg "fontspec.sty" && to_install+=("fontspec");;
      geometry) ! has_pkg "geometry.sty" && to_install+=("geometry");;
      "lualatex-math") ! has_pkg "lualatex-math.sty" && to_install+=("lualatex-math");;
      # umbrella collections to reduce future misses:
      collection-latexrecommended) to_install+=("collection-latexrecommended");;
      collection-fontsrecommended) to_install+=("collection-fontsrecommended");;
      *) to_install+=("$pkg");;
    esac
  done

  if ((${#to_install[@]})); then
    echo -e "${BLUE}Installing TeX packages (this may take a minute):${NC} ${to_install[*]}"
    if sudo tlmgr install "${to_install[@]}"; then
      return 0
    else
      echo -e "${YELLOW}Some TeX packages failed to install.${NC}"
      return 1
    fi
  fi
  return 0
}

ensure_engine_packages() {
  local engine="$1"
  local pkgs=( "${REQUIRED_PKGS_COMMON[@]}" geometry )
  case "$engine" in
    lualatex) pkgs+=( "${REQUIRED_PKGS_XELUA[@]}" "${REQUIRED_PKGS_LUALATEX[@]}" );;
    xelatex)  pkgs+=( "${REQUIRED_PKGS_XELUA[@]}" );;
    pdflatex) pkgs+=( );;
  esac
  # Try to install recommended formatting packages like titlesec (nice headers)
  pkgs+=( "${RECOMMENDED_FORMATTING_PKGS[@]}" "collection-latexrecommended" "collection-fontsrecommended" )

  install_pkgs_tlmgr "${pkgs[@]}" || return 1
  return 0
}

# -----------------------------
# Headers
# -----------------------------
make_base_header() {
  local header_path="$1"
  cat > "$header_path" <<'TEX'
\usepackage{xcolor}
\usepackage{enumitem}
\usepackage{microtype}
\usepackage[T1]{fontenc}

\definecolor{headercolor}{RGB}{44,62,80}
\definecolor{accentcolor}{RGB}{52,152,219}
\definecolor{textcolor}{RGB}{33,37,41}
\color{textcolor}

\setlist{itemsep=0.3em}
\setlength{\parskip}{0.6em}
TEX
}

# Optional nice section formatting (requires titlesec)
maybe_add_titlesec() {
  local header_path="$1"
  if has_pkg "titlesec.sty"; then
    cat >> "$header_path" <<'TEX'
\usepackage{titlesec}
\titleformat{\section}{\Large\bfseries\color{headercolor}}{\thesection}{1em}{}[\titlerule]
\titleformat{\subsection}{\large\bfseries\color{headercolor}}{\thesubsection}{1em}{}
\titleformat{\subsubsection}{\normalsize\bfseries\color{headercolor}}{\thesubsubsection}{1em}{}
\titlespacing*{\section}{0pt}{1.5em}{0.8em}
\titlespacing*{\subsection}{0pt}{1.2em}{0.6em}
\titlespacing*{\subsubsection}{0pt}{1em}{0.4em}
TEX
    $VERBOSE && echo -e "${GREEN}Using titlesec for section styling.${NC}"
  else
    $VERBOSE && echo -e "${YELLOW}titlesec.sty not found; using default section styles.${NC}"
  fi
}

augment_for_xe_or_lua() {
  local header_path="$1"
  cat >> "$header_path" <<'TEX'
\usepackage{fontspec}
\setmainfont{Avenir Next}[
  UprightFont     = *,
  BoldFont        = * Bold,
  ItalicFont      = * Italic,
  BoldItalicFont  = * Bold Italic
]
\setsansfont{Avenir Next}
\setmonofont{Source Code Pro}[Scale=0.95]
TEX
}

augment_for_pdflatex() {
  local header_path="$1"
  cat >> "$header_path" <<'TEX'
\usepackage[utf8]{inputenc}
% Map a few emojis to text so pdfLaTeX doesn't warn:
\DeclareUnicodeCharacter{1F4E7}{[email]}    % 📧
\DeclareUnicodeCharacter{1F4F1}{[mobile]}   % 📱
\DeclareUnicodeCharacter{1F4BB}{[laptop]}   % 💻
\DeclareUnicodeCharacter{1F4CD}{[location]} % 📍
TEX
}

# -----------------------------
# Pandoc runner
# -----------------------------
run_pandoc() {
  local engine="$1"
  local header_file="$2"

  local cmd=( pandoc "$INPUT_FILE"
    --pdf-engine="$engine"
    -H "$header_file"
    -V geometry:top=0.8in,bottom=0.8in,left=0.8in,right=0.8in
    -V fontsize=11pt
    -V documentclass=article
    -V papersize=letter
    -V colorlinks=true
    -V linkcolor="[RGB]{52,73,94}"
    -V urlcolor="[RGB]{52,152,219}"
    -V toccolor="[RGB]{44,62,80}"
    -V linestretch=1.15
    -V indent=false
    --syntax-highlighting=tango
    -o "$OUTPUT_FILE"
  )

  $VERBOSE && { echo -e "${BLUE}Running ${engine} with command:${NC}"; printf '  %q ' "${cmd[@]}"; echo; }

  if "${cmd[@]}" 2> >( $VERBOSE && cat >&2 || cat >/dev/null ); then
    return 0
  else
    return 1
  fi
}

# Try conversion with an engine; auto-install missing pkgs once if needed.
try_engine() {
  local engine="$1"
  if ! command -v "$engine" >/dev/null 2>&1; then
    $VERBOSE && echo -e "${YELLOW}Skipping ${engine}: not installed${NC}"
    return 1
  fi

  echo -e "${BLUE}Trying PDF conversion with ${engine}...${NC}"
  local TMP_HEADER; TMP_HEADER="$(mktemp -t cv_header.XXXXXX.tex)"
  make_base_header "$TMP_HEADER"
  maybe_add_titlesec "$TMP_HEADER"

  case "$engine" in
    lualatex|xelatex) augment_for_xe_or_lua "$TMP_HEADER";;
    pdflatex)         augment_for_pdflatex "$TMP_HEADER";;
  esac

  if run_pandoc "$engine" "$TMP_HEADER"; then
    rm -f "$TMP_HEADER"; return 0
  fi

  # First failure → try to install packages and retry once.
  echo -e "${YELLOW}Conversion with ${engine} failed. Checking/Installing TeX packages...${NC}"
  if ensure_engine_packages "$engine"; then
    # Recreate header (titlesec may now exist)
    rm -f "$TMP_HEADER"; TMP_HEADER="$(mktemp -t cv_header.XXXXXX.tex)"
    make_base_header "$TMP_HEADER"
    maybe_add_titlesec "$TMP_HEADER"
    case "$engine" in
      lualatex|xelatex) augment_for_xe_or_lua "$TMP_HEADER";;
      pdflatex)         augment_for_pdflatex "$TMP_HEADER";;
    esac

    if run_pandoc "$engine" "$TMP_HEADER"; then
      rm -f "$TMP_HEADER"; return 0
    fi
  else
    $VERBOSE && echo -e "${YELLOW}Package install step skipped/failed; proceeding to next engine.${NC}"
  fi

  rm -f "$TMP_HEADER"
  return 1
}

try_pdf_conversion() {
  for engine in "${ENGINES[@]}"; do
    if try_engine "$engine"; then
      return 0
    else
      echo -e "${YELLOW}Conversion with ${engine} failed, trying next engine...${NC}"
    fi
  done
  return 1
}

# -----------------------------
# HTML fallback (manual print)
# -----------------------------
html_to_pdf_fallback() {
  echo -e "${BLUE}Attempting HTML → PDF conversion...${NC}"
  local html_file="${OUTPUT_FILE%.pdf}.html"

  local css_file; css_file="$(mktemp -t cv_style.XXXXXX.css)"
  cat > "$css_file" <<'EOF'
body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  line-height: 1.6; max-width: 8.5in; margin: 0 auto; padding: 0.75in; color: #333;
}
h1, h2, h3 { color: #2c3e50; margin-top: 1.5em; }
h1 { border-bottom: 2px solid #3498db; padding-bottom: 0.3em; }
h2 { border-bottom: 1px solid #bdc3c7; padding-bottom: 0.2em; }
a { color: #3498db; text-decoration: none; }
a:hover { text-decoration: underline; }
code { background-color: #f8f9fa; padding: 0.2em 0.4em; border-radius: 3px; }
blockquote { border-left: 4px solid #3498db; margin-left: 0; padding-left: 1em; }
.email { word-break: break-all; }
@media print {
  body { margin: 0; padding: 0.5in; }
  * { -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }
}
EOF

  if pandoc "$INPUT_FILE" -o "$html_file" --standalone --css="$css_file"; then
    echo -e "${GREEN}✅ HTML version created: ${html_file}${NC}"
    echo -e "${YELLOW}To convert to PDF:${NC}"
    echo -e "1. Open: ${html_file}"
    echo -e "2. Press Cmd+P (Print)"
    echo -e "3. Choose 'Save as PDF'"
    echo -e "4. Disable headers/footers in print settings"
    echo -e "5. Save as: ${OUTPUT_FILE}"
    if [[ "$OSTYPE" == "darwin"* ]] && command -v open >/dev/null 2>&1; then
      echo; read -r -p "Press Enter to open HTML file for manual PDF conversion, or Ctrl+C to cancel..." _
      open "$html_file"
    fi
    rm -f "$css_file"; return 0
  else
    rm -f "$css_file"; return 1
  fi
}

# -----------------------------
# Main
# -----------------------------
echo -e "${BLUE}Starting PDF conversion...${NC}"

if $LATEX_AVAILABLE && try_pdf_conversion; then
  echo -e "${GREEN}✅ Success!${NC} PDF generated: ${OUTPUT_FILE}"
  if command -v ls >/dev/null 2>&1; then
    FILE_SIZE=$(ls -lh "$OUTPUT_FILE" | awk '{print $5}')
    echo -e "   File size: ${FILE_SIZE}"
  fi
  if [[ "$OSTYPE" == "darwin"* ]] && command -v open >/dev/null 2>&1; then
    echo; read -r -p "Press Enter to open PDF, or Ctrl+C to cancel..." _; open "$OUTPUT_FILE"
  fi
elif html_to_pdf_fallback; then
  echo -e "${YELLOW}PDF conversion via LaTeX failed, but HTML version is ready for manual conversion.${NC}"
else
  echo -e "${RED}❌ Error: All conversion methods failed!${NC}"
  echo -e "${YELLOW}Alternatives:${NC}"
  echo -e "1) brew install --cask mactex-no-gui   # full MacTeX without the GUI (larger, but everything there)"
  echo -e "2) or: sudo tlmgr update --self && sudo tlmgr install collection-latexrecommended collection-fontsrecommended"
  echo -e "3) or: pandoc \"$INPUT_FILE\" -o temp.html && open temp.html  (then Print → Save as PDF)"
  exit 1
fi

echo
echo -e "${GREEN}🎉 Ready for your LANL application!${NC}"
echo -e "${BLUE}Final checklist:${NC}"
echo -e "• Review the PDF formatting and layout"
echo -e "• Verify all contact information is correct"
echo -e "• Ensure technical portfolio repository is accessible"
echo -e "• Prepare elevator pitch about your transition story"
echo -e "• Practice explaining specific technical achievements"
