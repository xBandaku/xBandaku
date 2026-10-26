$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$user = 'xBandaku'
$headers = @{ Accept = 'application/vnd.github+json'; 'User-Agent' = 'xBandaku-profile'; 'X-GitHub-Api-Version' = '2022-11-28' }
if ($env:GH_TOKEN) { $headers.Authorization = 'Bearer ' + $env:GH_TOKEN }
function Get-PublicData([string]$path) {
    $data = Invoke-RestMethod -Uri ('https://api.github.com/' + $path) -Headers $headers
    foreach ($item in $data) { Write-Output $item }
}
function Safe-Text([string]$text) {
    $text = [Net.WebUtility]::HtmlEncode(($text -replace '[\r\n]+', ' '))
    [regex]::Replace($text, '([\\`*_{}\[\]()#!|~])', '\$1')
}
function Repo-Line($repo) {
    $line = '- [' + (Safe-Text $repo.full_name) + '](' + $repo.html_url + ')'
    if ($repo.description) { $line += ' — ' + (Safe-Text $repo.description) }
    $line
}
$repos = @()
$page = 1
do {
    $batch = @(Get-PublicData "users/$user/repos?type=owner&per_page=100&page=$page")
    $repos += $batch | Where-Object { !$_.private -and $_.name -ne $user }
    $page++
} while ($batch.Count -eq 100)
$latest = @($repos | Where-Object { !$_.fork } | Sort-Object created_at -Descending | Select-Object -First 5)
$query = [Uri]::EscapeDataString("author:$user is:pr is:public")
$pulls = Get-PublicData "search/issues?q=$query&sort=updated&order=desc&per_page=5"
$stars = @(Get-PublicData "users/$user/starred?per_page=5&sort=created&direction=desc")
$sections = @{
    projects = ($latest | ForEach-Object { Repo-Line $_ }) -join "`n"
    prs = ($pulls.items | ForEach-Object {
        $repoName = ($_.repository_url -split '/repos/')[1]
        '- [' + (Safe-Text $_.title) + '](' + $_.html_url + ') on [' + (Safe-Text $repoName) + '](https://github.com/' + $repoName + ')'
    }) -join "`n"
    stars = ($stars | ForEach-Object { Repo-Line $_ }) -join "`n"
}
$readmePath = Join-Path $root 'README.md'
$readme = [IO.File]::ReadAllText($readmePath)
foreach ($key in $sections.Keys) {
    $pattern = '(?s)<!-- ' + $key + ':start -->.*?<!-- ' + $key + ':end -->'
    if (![regex]::IsMatch($readme, $pattern)) { throw "Missing README section: $key" }
    $replacement = "<!-- ${key}:start -->`n" + $sections[$key] + "`n<!-- ${key}:end -->"
    $readme = [regex]::Replace($readme, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $replacement })
}
$original = @($repos | Where-Object { !$_.fork })
$starCount = ($repos | Measure-Object stargazers_count -Sum).Sum
$languages = @($original | Where-Object language | Select-Object -ExpandProperty language -Unique)
$values = @($repos.Count, $starCount, $original.Count, $languages.Count)
$labels = @('PUBLIC REPOS', 'REPO STARS', 'ORIGINAL PROJECTS', 'LANGUAGES')
$cards = for ($i = 0; $i -lt 4; $i++) {
    $x = 28 + 220 * $i
    '<text x="' + $x + '" y="53" fill="#f1f6fc" font-size="30" font-weight="700">' + $values[$i] + '</text>' +
    '<text x="' + $x + '" y="82" fill="#91a6bc" font-size="11" letter-spacing="1.2">' + $labels[$i] + '</text>'
}
$svg = '<svg xmlns="http://www.w3.org/2000/svg" width="900" height="108" viewBox="0 0 900 108" role="img" aria-labelledby="title"><title id="title">Public project statistics for xBandaku, excluding the profile repository</title><rect width="900" height="108" rx="12" fill="#0d1623"/><path d="M225 24v60m220-60v60m220-60v60" stroke="#263a4e"/><g font-family="Segoe UI,Arial,sans-serif">' + ($cards -join '') + '</g></svg>'
# Fetch everything before writing so an API failure preserves the last good profile.
[IO.File]::WriteAllText((Join-Path $root 'assets/stats.svg'), $svg + "`n")
[IO.File]::WriteAllText($readmePath, $readme)
Write-Output 'Updated public projects, pull requests, stars, and repository statistics.'
