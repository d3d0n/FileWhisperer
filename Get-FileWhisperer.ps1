# Requires -Version 5.0

$GEMINI_API_ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models"
$GEMINI_MODEL = "gemini-2.0-flash"
$GEMINI_VISION_MODEL = "gemini-2.0-flash"
$TOGETHER_API_ENDPOINT = "https://api.together.xyz/v1/chat/completions"
$TOGETHER_MODEL = "meta-llama/Llama-3.2-3B-Instruct-Turbo"

$MAX_FILES_IN_DIR = 500  
$MAX_FILE_SIZE_KB = 500  
$MAX_SIBLINGS_TO_SHOW = 50  
$MAX_CONTENT_PREVIEW = 5000  
$MAX_PROMPT_LENGTH = 30000  

$IMPORTANCE_THRESHOLD = 5.0  
$MAX_IMPORTANT_SIBLINGS = 5  

$TOGETHER_SETTINGS = @{
    temperature = 0.7        
    top_p       = 0.7             
    top_k       = 50              
    max_tokens  = 2048       
    repetition_penalty = 1.1
}

function Load-EnvFile {
    param (
        [string]$envFile = ".env"
    )
    if (Test-Path $envFile) {
        Get-Content $envFile | ForEach-Object {
            if ($_ -match '^[^#]') {
                $name, $value = $_.split('=', 2)
                if ($name -and $value) {
                    Set-Item -Path "env:$name" -Value $value.Trim('"')
                }
            }
        }
    }
    else {
        Write-Warning "File $envFile not found"
    }
}

Load-EnvFile

function Write-DebugInfo {
    param(
        [string]$Message,
        [object]$Data
    )
    Write-Host "DEBUG: $Message" -ForegroundColor Yellow
    if ($Data) {
        Write-Host ($Data | ConvertTo-Json -Depth 5) -ForegroundColor Cyan
    }
}

function Get-FileMetadata {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    $item = Get-Item $Path
    $metadata = @{
        Name         = $item.Name
        FullPath     = $item.FullName
        CreationTime = $item.CreationTime.ToString("yyyy-MM-dd HH:mm:ss")
        LastWriteTime= $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        Extension    = $item.Extension
        Size         = if ($item.PSIsContainer) { (Get-ChildItem $item.FullName -Recurse | Measure-Object -Property Length -Sum).Sum } else { $item.Length }
        Type         = if ($item.PSIsContainer) { "Directory" } else { "File" }
    }
    return $metadata
}

function Test-IsBinaryFile {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    $binaryExtensions = @('.exe', '.dll', '.zip', '.rar', '.7z', '.png', '.jpg', '.jpeg', '.gif', '.pdf', '.doc', '.docx', '.xls', '.xlsx')
    $extension = [System.IO.Path]::GetExtension($Path).ToLower()
    return $binaryExtensions -contains $extension
}

function Get-SmartFilePreview {
    param (
        [string]$Content,
        [int]$MaxLength = $MAX_CONTENT_PREVIEW
    )
    if ($Content.Length -le $MaxLength) {
        return $Content
    }
    $firstPart = $Content.Substring(0, [Math]::Floor($MaxLength/2))
    $lastPart  = $Content.Substring($Content.Length - [Math]::Floor($MaxLength/2))
    return "$firstPart`n...[CONTENT TRUNCATED]...`n$lastPart"
}

function Get-FileImportanceScore {
    param (
        [Parameter(Mandatory = $true)]
        [System.IO.FileSystemInfo]$File,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )
    $score = 0.0
    $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)
    $targetNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($TargetPath)
    if ($nameWithoutExt -eq $targetNameWithoutExt) { $score += 3.0 }
    elseif ($nameWithoutExt.Contains($targetNameWithoutExt) -or $targetNameWithoutExt.Contains($nameWithoutExt)) { $score += 2.0 }
    elseif ($nameWithoutExt.ToLower().Contains($targetNameWithoutExt.ToLower())) { $score += 1.0 }
    $targetIsDirectory = (Get-Item $TargetPath).PSIsContainer
    if ($File.PSIsContainer -eq $targetIsDirectory) {
        $score += 1.0  
        if (-not $File.PSIsContainer) {
            if ($File.Extension -eq [System.IO.Path]::GetExtension($TargetPath)) {
                $score += 1.0
            }
        }
    }
    $targetItem = Get-Item $TargetPath
    $timeDiff = [Math]::Abs(($File.LastWriteTime - $targetItem.LastWriteTime).TotalHours)
    if ($timeDiff -lt 1) { $score += 2.0 }
    elseif ($timeDiff -lt 24) { $score += 1.0 }
    if (-not $File.PSIsContainer -and -not $targetIsDirectory) {
        $targetSize = $targetItem.Length
        $sizeDiffRatio = if ($targetSize -eq 0) { 1 } else { [Math]::Abs($File.Length - $targetSize) / $targetSize }
        if ($sizeDiffRatio -lt 0.1) { $score += 1.5 }
        elseif ($sizeDiffRatio -lt 0.5) { $score += 0.75 }
    }
    if (-not $File.PSIsContainer -and -not $targetIsDirectory) {
        $relatedPatterns = @{
            '.config' = @('.json', '.xml', '.yaml', '.yml', '.ini', '.conf')
            '.md'     = @('.txt', '.doc', '.docx', '.pdf')
            '.py'     = @('.pyc', '.pyw', '.ipynb', 'requirements.txt')
            '.js'     = @('.ts', '.jsx', '.tsx', 'package.json')
            '.cpp'    = @('.h', '.hpp', '.obj')
            '.cs'     = @('.csproj', '.sln', '.dll')
            '.ini'    = @('.ini', '.cfg', '.conf', '.config')
        }
        foreach ($pattern in $relatedPatterns.Keys) {
            if ($TargetPath.EndsWith($pattern)) {
                if ($relatedPatterns[$pattern] -contains $File.Extension) {
                    $score += 1.5
                    break
                }
            }
        }
    }
    return [Math]::Min(10.0, $score)
}

function Get-SiblingAnalysis {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )
    $siblingInfo = @{
        name     = (Get-Item $Path).Name
        score    = 0.0
        metadata = Get-FileMetadata -Path $Path
        preview  = $null
    }
    $siblingInfo.score = Get-FileImportanceScore -File (Get-Item $Path) -TargetPath $TargetPath
    if ($siblingInfo.score -ge $IMPORTANCE_THRESHOLD -and -not (Test-IsBinaryFile -Path $Path)) {
        try {
            $rawContent = Get-Content $Path -Raw -ErrorAction Stop
            $siblingInfo.preview = Get-SmartFilePreview -Content $rawContent
        }
        catch {
            $siblingInfo.preview = "Error reading file: $_"
        }
    }
    return $siblingInfo
}

function Convert-ImageToBase64 {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ImagePath
    )
    try {
        $imageBytes = [System.IO.File]::ReadAllBytes($ImagePath)
        return [System.Convert]::ToBase64String($imageBytes)
    }
    catch {
        Write-Error "Failed to convert image to base64: $_"
        return $null
    }
}

function Get-ImageDescription {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ImagePath,
        [string]$Prompt = "Describe this image in detail, including: the main subject, setting, lighting, colors, and any notable details or text visible in the image."
    )
    if (-not $env:GOOGLE_API_KEY) {
        Write-Error "GOOGLE_API_KEY env var not set. Gemini API needed."
        return $null
    }
    if (-not (Test-Path $ImagePath)) {
        Write-Error "Image file doesn't exist: $ImagePath"
        return $null
    }
    $extension = [System.IO.Path]::GetExtension($ImagePath).ToLower()
    $mimeType = switch ($extension) {
        ".jpg"  { "image/jpeg" }
        ".jpeg" { "image/jpeg" }
        ".png"  { "image/png" }
        ".webp" { "image/webp" }
        ".heic" { "image/heic" }
        default { 
            Write-Error "Unsupported image format: $extension. Supports: jpg, jpeg, png, webp, heic"
            return $null
        }
    }
    try {
        Write-DebugInfo "Start descr img" @{ path = $ImagePath; mimeType = $mimeType; prompt = $Prompt }
        $base64Image = Convert-ImageToBase64 -ImagePath $ImagePath
        if (-not $base64Image) { 
            Write-Error "Couldn't convert img to base64"
            return $null 
        }
        $body = @{
            contents = @(
                @{
                    parts = @(
                        @{ text = $Prompt },
                        @{
                            inline_data = @{
                                mime_type = $mimeType
                                data      = $base64Image
                            }
                        }
                    )
                }
            )
        }
        $jsonBody = $body | ConvertTo-Json -Depth 10 -Compress
        $tempJson = [System.IO.Path]::GetTempFileName()
        try {
            $jsonBody | Set-Content $tempJson -Encoding UTF8
            $apiUrl = "$GEMINI_API_ENDPOINT/$GEMINI_VISION_MODEL`:generateContent?key=$env:GOOGLE_API_KEY"
            Write-DebugInfo "Calling Gemini Vision API" @{ url = $apiUrl; imageSize = $base64Image.Length; prompt = $Prompt }
            $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers @{"Content-Type" = "application/json"} -InFile $tempJson -ErrorVariable responseError
            Write-DebugInfo "Got Gemini Vision resp" $response
            if ($response.candidates -and $response.candidates[0] -and $response.candidates[0].content -and $response.candidates[0].content.parts -and $response.candidates[0].content.parts[0].text) {
                return $response.candidates[0].content.parts[0].text
            } else {
                Write-Error "Unexpected resp format from Gemini Vision API"
                Write-DebugInfo "Invalid resp" $response
                return $null
            }
        }
        finally {
            if (Test-Path $tempJson) {
                Remove-Item $tempJson -Force
            }
        }
    }
    catch {
        $errorDetails = if ($responseError) { "API Err: $($responseError.Message)" } else { "Err: $_" }
        Write-DebugInfo "Img descr error" $errorDetails
        Write-Error "Failed to get img descr: $errorDetails"
        return $null
    }
}

function Build-BaseContentInfo {
    param([string]$Path)
    $metadata = Get-FileMetadata -Path $Path
    Write-DebugInfo "Got meta" $metadata
    $contentInfo = @{
        metadata = $metadata
        contents = @()
        context  = @{ 
            parentFolder      = Split-Path $Path -Parent
            siblingItems      = @()
            importantSiblings = @()
            summary           = @{ 
                totalItems = 0
                totalSize  = 0
                fileTypes  = @{}
            }
        }
    }
    return $contentInfo
}

function Process-ImageContent {
    param([string]$Path, [ref]$ContentInfo)
    $metadata = $ContentInfo.Value.metadata
    if ($metadata.Type -eq "File") {
         $imageExtensions = @('.jpg', '.jpeg', '.png', '.webp', '.heic')
         if ($imageExtensions -contains $metadata.Extension.ToLower()) {
             Write-DebugInfo "Processing img" @{ path = $Path; ext = $metadata.Extension }
             $imageDescription = Get-ImageDescription -ImagePath $Path
             if ($imageDescription) {
                  Write-DebugInfo "Got img descr" $imageDescription
                  $ContentInfo.Value.imageAnalysis = $imageDescription
             } else {
                  Write-DebugInfo "No img descr" "None returned"
             }
         }
    }
}

function Analyze-SiblingItems {
    param([string]$Path, [ref]$ContentInfo)
    $allSiblings = Get-ChildItem (Split-Path $Path -Parent) |
         Where-Object { $_.FullName -ne (Get-Item $Path).FullName } |
         ForEach-Object {
             @{ 
                 basic = @{ 
                     Name          = $_.Name
                     Extension     = if ($_.PSIsContainer) { "Directory" } else { $_.Extension }
                     LastWriteTime = $_.LastWriteTime
                     FullName      = $_.FullName
                     IsDirectory   = $_.PSIsContainer
                 }
                 importance = Get-FileImportanceScore -File $_ -TargetPath $Path
             }
         } | Sort-Object { $_.importance } -Descending
    $ContentInfo.Value.context.siblingItems = $allSiblings |
         Select-Object -First $MAX_SIBLINGS_TO_SHOW |
         ForEach-Object { $_.basic } | ConvertTo-Json
    $ContentInfo.Value.context.importantSiblings = $allSiblings |
         Where-Object { $_.importance -ge $IMPORTANCE_THRESHOLD } |
         Select-Object -First $MAX_IMPORTANT_SIBLINGS |
         ForEach-Object { 
              if ($_.basic.FullName) {
                   Get-SiblingAnalysis -Path $_.basic.FullName -TargetPath $Path
              }
         }
    Write-DebugInfo "Analyzed important sibs" $ContentInfo.Value.context.importantSiblings
}

function Build-FinalPrompt {
    param(
        [string]$TempFile,
        [ValidateSet("short", "long")]
        [string]$PromptVersion = "short"
    )
    if ($PromptVersion -eq "short") {
        $prompt = @"
You are a helpful assistant that provides a concise summary of a file system item in Windows. Analyze the provided content and metadata briefly. Your answer must include the following sections:

1. Metadata:
   - Basic information (name, type, full path, and size).

2. Content Analysis:
   - For directories: total items count, overall size, filenames and extensions.
   - For text files: a short preview (max 50 characters).
   - For binary files: metadata summary.
   - For image files: a brief description.

3. Relationships:
   - Up to 3 related files with clickable file links in the format <full_path>.

4. Summary:
   - A one-sentence overall assessment.

Do not use markdown formatting; plain text only.

Content and metadata:
$(Get-Content $TempFile -Raw)
"@
    }
    else {
        $prompt = @"
You are a helpful assistant that provides a detailed, structured summary of a file system item in Windows. Analyze the provided content and metadata thoroughly. Your response must include the following sections:

1. Metadata:
   - Include basic information (name, type, full path, creation time, modification time, size, etc.).
   - If the item is a directory, include the total number of files and their sizes
   - If the item is a file, include the size in KB/MB/GB
   - If the item is an image, include a brief description of the image content

2. Content Analysis:
   - For directories: describe the structure, file type distribution, total number of items, and overall size.
   - For text files: provide a concise preview with key highlights.
   - For binary files: focus on metadata and contextual details.
   - For image files: include an analysis of the image content and any available description.

3. Relationships and Context:
   - Analyze relationships with sibling or related files.
   - If you mention any file, include a clickable file link in the format full_path pointing to its location in the file system.

4. Statistics and Quantitative Data:
   - Include any relevant numerical data or statistics derived from the metadata.

5. Summary:
   - Provide an overall assessment of the object based on the above information.

Do not use markdown formatting; plain text only.

Content and metadata:
$(Get-Content $TempFile -Raw)
"@
    }
    return $prompt
}

function SummarizeDirectoryContent {
    param([string]$Path, [ref]$ContentInfo)
    $allItems = Get-ChildItem $Path -Recurse
    $ContentInfo.Value.context.summary.totalItems = $allItems.Count
    $ContentInfo.Value.context.summary.totalSize = ($allItems | Measure-Object -Property Length -Sum).Sum
    $allItems | Where-Object { -not $_.PSIsContainer } | ForEach-Object {
         $ext = if ($_.Extension) { $_.Extension.ToLower() } else { "(no extension)" }
         if ($ContentInfo.Value.context.summary.fileTypes.ContainsKey($ext)) {
              $ContentInfo.Value.context.summary.fileTypes[$ext]++
         } else {
              $ContentInfo.Value.context.summary.fileTypes[$ext] = 1
         }
    }
    $ContentInfo.Value.contents = Get-ChildItem $Path |
         Select-Object FullName, Name, Extension, LastWriteTime, Length |
         Select-Object -First $MAX_FILES_IN_DIR | ConvertTo-Json
    Write-DebugInfo "Dir contents" "Count: $($ContentInfo.Value.context.summary.totalItems)"
}

function SummarizeFileContent {
    param([string]$Path, [ref]$ContentInfo)
    if (-not (Test-IsBinaryFile -Path $Path)) {
         try {
              $fileSize = (Get-Item $Path).Length / 1KB
              if ($fileSize -gt $MAX_FILE_SIZE_KB) {
                   $ContentInfo.Value.contents = "File too large to show content ($('{0:N2}' -f $fileSize) KB). Showing metadata only."
              } else {
                   $rawContent = Get-Content $Path -Raw -ErrorAction Stop
                   $ContentInfo.Value.contents = Get-SmartFilePreview -Content $rawContent
              }
              Write-DebugInfo "File content" "Len: $($ContentInfo.Value.contents.Length)"
         }
         catch {
              $ContentInfo.Value.contents = "Error reading file contents: $_"
              Write-DebugInfo "File read err" $_
         }
    } else {
         if ($ContentInfo.Value.imageAnalysis) {
              $ContentInfo.Value.contents = $ContentInfo.Value.imageAnalysis
         } else {
              $ContentInfo.Value.contents = "Binary file - content not included"
         }
    }
}

function Get-ContentSummary {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [ValidateSet("short", "long")]
        [string]$PromptVersion = "short"
    )
    $tempFile = [System.IO.Path]::GetTempFileName()
    Write-DebugInfo "Temp file" $tempFile
    $contentInfo = Build-BaseContentInfo -Path $Path
    Process-ImageContent -Path $Path -ContentInfo ([ref]$contentInfo)
    Analyze-SiblingItems -Path $Path -ContentInfo ([ref]$contentInfo)
    if ($contentInfo.metadata.Type -eq "Directory") {
         SummarizeDirectoryContent -Path $Path -ContentInfo ([ref]$contentInfo)
    } else {
         SummarizeFileContent -Path $Path -ContentInfo ([ref]$contentInfo)
    }
    $currentDate = Get-Date
    $contentInfo.context.currentDate = $currentDate.ToString("yyyy-MM-dd HH:mm:ss")
    $contentInfo | ConvertTo-Json -Depth 10 | Set-Content $tempFile -Encoding UTF8
    Write-DebugInfo "Saved info" $tempFile
    $prompt = Build-FinalPrompt -TempFile $tempFile -PromptVersion $PromptVersion
    if ($prompt.Length -gt $MAX_PROMPT_LENGTH) {
         $prompt = $prompt.Substring(0, $MAX_PROMPT_LENGTH) + "`n...[Content truncated due to length]..."
    }
    Write-DebugInfo "Prompt ready" "Len: $($prompt.Length)"
    try {
         if ($env:USE_TOGETHER_API -eq "true") {
              if (-not $env:TOGETHER_API_KEY) {
                   throw "TOGETHER_API_KEY env var not set. Set it with your Together AI API key."
              }
              $headers = @{ "Authorization" = "Bearer $env:TOGETHER_API_KEY"; "Content-Type" = "application/json" }
              $messages = @(
                   @{ role = "system"; content = "You are a helpful assistant that provides detailed summaries of file system items in Windows." },
                   @{ role = "user"; content = $prompt }
              )
              $body = @{ model = $TOGETHER_MODEL; messages = $messages; temperature = $TOGETHER_SETTINGS.temperature; top_p = $TOGETHER_SETTINGS.top_p; top_k = $TOGETHER_SETTINGS.top_k; max_tokens = $TOGETHER_SETTINGS.max_tokens; repetition_penalty = $TOGETHER_SETTINGS.repetition_penalty }
              $jsonBody = $body | ConvertTo-Json -Depth 10 -Compress
              Write-DebugInfo "Together req body" "Len: $($jsonBody.Length)"
              try {
                  $response = Invoke-RestMethod -Uri $TOGETHER_API_ENDPOINT -Method Post -Headers $headers -Body $jsonBody -ContentType "application/json" -ErrorVariable responseError
                  Write-DebugInfo "Together resp" $response
                  if ($response.choices -and $response.choices.Count -gt 0 -and $response.choices[0].message) {
                        $result = $response.choices[0].message.content
                  } else {
                        throw "Unexpected response format from Together AI API"
                  }
              }
              catch {
                  $errorMessage = if ($responseError) { "Together AI API err: $($responseError.Message)" } else { "Err calling Together AI API: $_" }
                  throw $errorMessage
              }
         }
         else {
              $headers = @{ "Content-Type" = "application/json" }
              $apiUrl = "$GEMINI_API_ENDPOINT/$GEMINI_MODEL`:generateContent?key=$env:GOOGLE_API_KEY"
              Write-DebugInfo "API URL" $apiUrl
              $body = @{ contents = @(@{ parts = @(@{ text = $prompt }) }) }
              $jsonBody = $body | ConvertTo-Json -Depth 10 -Compress
              $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -Body $jsonBody
              Write-DebugInfo "Gemini resp" $response
              $result = $response.candidates[0].content.parts[0].text
         }
         Remove-Item $tempFile -Force
         Write-DebugInfo "Cleaned temp file" $tempFile
         return $result
    }
    catch {
         Write-DebugInfo "API call err" $_
         Write-Error "API error: $_"
         return $null
    }
}

function Get-ExplorerSummary {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$s,
        [switch]$l
    )
    if ($env:USE_TOGETHER_API -eq "true") {
        if (-not $env:TOGETHER_API_KEY) {
            Write-Error "TOGETHER_API_KEY env var not set. Set it with your Together AI API key."
            return
        }
    }
    elseif (-not $env:GOOGLE_API_KEY) {
        Write-Error "GOOGLE_API_KEY env var not set. Set it or use Together AI by setting USE_TOGETHER_API=true"
        return
    }
    if (-not (Test-Path $Path)) {
        Write-Error "Path doesn't exist: $Path"
        return
    }
    $promptVersion = if ($l) { "long" } else { "short" }
    return Get-ContentSummary -Path $Path -PromptVersion $promptVersion
}