# FileWhisperer: AI-Powered CLI File Analysis & Summarization written in PowerShell

FileWhisperer is an advanced PowerShell script designed to deliver intelligent, context-aware summaries of files and directories on Windows. Leveraging the power of Google's Gemini AI (or Together AI if preferred), it not only analyzes file content but also metadata and sibling relationships to provide detailed insights for effective file management.

## Key Features & Functionality

- **Content Analysis**
  - Analyzes both files and directories with a tailored approach for text and binary files.
  - Provides concise previews for text files and informative metadata summaries for binary files.
  - Generates detailed directory statistics including total item counts, size summaries, and file type breakdowns.

- **AI-Powered Summaries**
  - Utilizes Google's Gemini AI for analysis, or Together AI if configured.
  - Offers both short and detailed report versions based on user preference.
  - Summaries include clear sections: metadata, content analysis, relationships with other files, and a final overall assessment.

- **File Relationship Scoring**
  - Implements a scoring system (0 to 10) assessing file relationships through name similarity, type matching, timestamp proximity, size comparisons, and pattern recognition.
  - Highlights up to three related files with clickable links to their full paths.

- **Context-Aware Sibling/Subdirectory Analysis**
  - Analyzes neighboring files in the directory to gather context and identify important related items.

- **Image Content Analysis**
  - For supported image formats (JPG, JPEG, PNG, WEBP, HEIC), provides a brief descriptive analysis of the image content using Gemini Vision API.

## Setup & Prerequisites

Before using FileWhisperer, ensure you meet the following prerequisites:

- **PowerShell 5.0 or Later:** The script requires modern PowerShell capabilities.
- **API Keys:**
  - For Google's Gemini AI, set your API key:
    ```powershell
    $env:GOOGLE_API_KEY = "your-google-gemini-api-key"
    ```
  - Alternatively, to use Together AI, enable it and set your key:
    ```powershell
    $env:USE_TOGETHER_API = "true"
    $env:TOGETHER_API_KEY = "your-together-ai-api-key"
    ```
- **Internet Connection:** Required for API access.
- **Script Download:** Download the `explorersummary.ps1` script into your working environment.

## Installation and Configuration

1. **Download the Script**
   - Place `Get-FileWhisperer.ps1` into your preferred working directory.

2. **Configure Your API Key**
   - Open the script and insert your API key as shown above to enable AI-powered analysis.
   - Get your API keys from the following links:
     - [Google Gemini API](https://aistudio.google.com/apikey)
     - [Together AI](https://api.together.ai/settings/api-keys)

3. **Adjust Configurable Settings**
   - The script allows you to fine-tune its behavior with several constants:
     ```powershell
     # Analysis Size Limits
     $MAX_FILES_IN_DIR = 500        # Max files to list during directory analysis
     $MAX_FILE_SIZE_KB = 1000       # Max file size for full content analysis
     $MAX_SIBLINGS_TO_SHOW = 500    # Max sibling files to analyze for context
     $MAX_CONTENT_PREVIEW = 10000   # Max characters for file content preview

     # Relationship Scoring Thresholds
     $IMPORTANCE_THRESHOLD = 5.0     # Minimum score for deep related-file analysis
     $MAX_IMPORTANT_SIBLINGS = 5     # Max important sibling files to include
     ```

## Usage Examples

### Basic Commands

Load the script and run summaries on files or directories:

```powershell
# Import the script
. .\Get-FileWhisperer.ps1

# Summarize a specific file briefly
Get-ExplorerSummary -Path "C:\Path\To\Your\File.txt" -s

# Summarize a specific file in detail
Get-ExplorerSummary -Path "C:\Path\To\Your\File.txt" -l

# Summarize a picture
Get-ExplorerSummary -Path "C:\Path\To\Your\Picture.jpg" -l
```

### Sample Outputs

For a **text file**, you might see a summary like:
```
Configuration file (INI format) with key settings for user preferences.
Preview: A short snippet of the file content...
Related files: Other INI files in the directory (clickable paths).
Last modified: [timestamp]
```

For a **directory**, the summary could include:
```
Directory Summary: 50 files with a total size of 1.2GB.
File Types Breakdown: .txt (15), .pdf (10), .docx (25).
Highlights of recent modifications indicating active usage.
```

## Debugging and Error Handling

- **Debug Mode:** The script outputs detailed debug information including file metadata, analysis steps, API interactions, scoring calculations, and error messages.
- **Error Handling:** Built-in checks address issues such as:
  - Invalid file paths or access problems
  - Missing API keys
  - Failures during file content retrieval or API communication
  - Handling for large files and non-text (binary) content

## Supported File Types & Relationships

FileWhisperer supports a variety of common file relationships, including:

- **Configuration Files:** (.config, .json, .xml, .yaml, .ini)
- **Documentation:** (.md, .txt, .doc, .pdf)
- **Dev:**
  - Python: (.py, .pyc, .pyw, requirements.txt)
  - JavaScript/TypeScript: (.js, .ts, .jsx, package.json)
  - C++: (.cpp, .h, .hpp)
  - C#: (.cs, .csproj, .sln)

## TODO

- [ ] Add relationships between more files
- [ ] Add structured output for gemini
- [ ] Add a README section to setup script to import on every new powershell session

# License
[MIT](https://github.com/d3d0n/FileWhisperer/blob/main/LICENSE)
