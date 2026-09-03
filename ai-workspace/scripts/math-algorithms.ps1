<#
.SYNOPSIS
  Shared Mathematical and Algorithmic Engine for Universal AI Workflow.
  Grounding:
    - Information Theory (Shannon Entropy, Rate-Distortion, Tishby's Information Bottleneck)
    - Probabilistic Information Retrieval (Robertson-Spärck Jones Okapi BM25+)
    - Cognitive Science & Memory Activation (Anderson's ACT-R, Ebbinghaus Forgetting Curve)
    - Graph Spectral Theory & Link Analysis (Brin-Page Personalized PageRank via Power Iteration)
#>

# ═══════════════════════════════════════════════════════════════════════════════
# 1. PROBABILISTIC INFORMATION RETRIEVAL: OKAPI BM25+
# ═══════════════════════════════════════════════════════════════════════════════

function Get-Tokens {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    # Tokenize on non-alphanumeric, split camelCase / snake_case, lowercase, filter >= 2 chars
    $rawTokens = [regex]::Replace($Text, '([a-z])([A-Z])', '$1 $2') -split '[^a-zA-Z0-9_\-/]+' |
        ForEach-Object { $_.Trim().ToLower() } |
        Where-Object { $_.Length -ge 2 }
    return @($rawTokens)
}

function Get-CharacterNgrams {
    param([string]$Text, [int]$N = 3)
    $clean = $Text.ToLower().Trim()
    if ($clean.Length -lt $N) { return @($clean) }
    $ngrams = @()
    for ($i = 0; $i -le ($clean.Length - $N); $i++) {
        $ngrams += $clean.Substring($i, $N)
    }
    return @($ngrams | Select-Object -Unique)
}

function Get-JaccardSimilarity {
    param([string]$TextA, [string]$TextB, [int]$Ngram = 3)
    $setA = Get-CharacterNgrams -Text $TextA -N $Ngram
    $setB = Get-CharacterNgrams -Text $TextB -N $Ngram
    if ($setA.Count -eq 0 -and $setB.Count -eq 0) { return 1.0 }
    if ($setA.Count -eq 0 -or $setB.Count -eq 0) { return 0.0 }
    
    $intersection = 0
    $dictB = @{}
    foreach ($item in $setB) { $dictB[$item] = $true }
    foreach ($item in $setA) { if ($dictB.ContainsKey($item)) { $intersection++ } }
    
    $union = $setA.Count + $setB.Count - $intersection
    if ($union -le 0) { return 0.0 }
    return [Math]::Round(($intersection / [double]$union), 4)
}

function Get-BM25PlusScore {
    <#
    .SYNOPSIS
      Computes BM25+ relevance score between query terms and a document.
      BM25+ incorporates delta parameter (delta = 1.0) to guarantee lower-bound
      relevance for long documents containing rare matching terms.
    #>
    param(
        [string[]]$QueryTerms,
        [string[]]$DocTokens,
        [double]$AvgDocLength,
        [hashtable]$CorpusDocFreq,  # term -> document frequency n(q)
        [int]$CorpusDocCount,      # Total documents N
        [double]$K1 = 1.5,
        [double]$B = 0.75,
        [double]$Delta = 1.0
    )
    if (-not $QueryTerms -or $QueryTerms.Count -eq 0 -or -not $DocTokens -or $DocTokens.Count -eq 0) {
        return 0.0
    }

    $docLength = $DocTokens.Count
    $lenNorm = 1.0 - $B + ($B * ($docLength / [Math]::Max(1.0, $AvgDocLength)))
    
    # Compute Term Frequencies in Document
    $tf = @{}
    foreach ($t in $DocTokens) {
        if ($tf.ContainsKey($t)) { $tf[$t]++ } else { $tf[$t] = 1 }
    }

    $score = 0.0
    $N = [Math]::Max(1, $CorpusDocCount)

    foreach ($q in $QueryTerms) {
        $qLower = $q.ToLower()
        $f = if ($tf.ContainsKey($qLower)) { [double]$tf[$qLower] } else { 0.0 }
        if ($f -le 0) { continue }

        # Document frequency n(q)
        $nq = if ($null -ne $CorpusDocFreq -and $CorpusDocFreq.ContainsKey($qLower)) { [double]$CorpusDocFreq[$qLower] } else { 1.0 }
        
        # Robertson-Spärck Jones IDF with smoothing
        # IDF(q) = ln( (N - n(q) + 0.5) / (n(q) + 0.5) + 1.0 )
        $idf = [Math]::Log((($N - $nq + 0.5) / ($nq + 0.5)) + 1.0)
        if ($idf -lt 0) { $idf = 0.01 }

        # BM25+ Term Weighting: IDF * ( (f * (k1 + 1)) / (f + k1 * lenNorm) + delta )
        $termScore = $idf * ((($f * ($K1 + 1.0)) / ($f + ($K1 * $lenNorm))) + $Delta)
        $score += $termScore
    }

    return [Math]::Round($score, 4)
}

# ═══════════════════════════════════════════════════════════════════════════════
# 2. COGNITIVE MEMORY: ACT-R BASE-LEVEL ACTIVATION & EBBINGHAUS DECAY
# ═══════════════════════════════════════════════════════════════════════════════

function Invoke-BM25PlusRank {
    <#
    .SYNOPSIS
      High-level wrapper to rank a list of string documents against query terms.
    #>
    param(
        [string[]]$QueryTerms,
        [string[]]$CorpusDocs
    )
    $N = $CorpusDocs.Count
    if ($N -eq 0) { return @() }

    # Tokenize corpus and calculate average document length & doc frequencies
    $docTokensList = @()
    $totalLen = 0
    $CorpusDocFreq = @{}

    foreach ($doc in $CorpusDocs) {
        $tokens = Get-Tokens -Text $doc
        $docTokensList += ,$tokens
        $totalLen += $tokens.Count

        $uniqueTokens = $tokens | Select-Object -Unique
        foreach ($t in $uniqueTokens) {
            if ($CorpusDocFreq.ContainsKey($t)) { $CorpusDocFreq[$t]++ }
            else { $CorpusDocFreq[$t] = 1 }
        }
    }
    $avgDl = $totalLen / [double]$N
    if ($avgDl -eq 0) { $avgDl = 1.0 }

    $scored = @()
    for ($i = 0; $i -lt $N; $i++) {
        $doc = $CorpusDocs[$i]
        $tokens = $docTokensList[$i]
        $score = Get-BM25PlusScore -QueryTerms $QueryTerms -DocTokens $tokens -AvgDocLength $avgDl -CorpusDocFreq $CorpusDocFreq -CorpusDocCount $N
        if ($score -gt 0) {
            $scored += [pscustomobject]@{ Score = $score; Original = $doc; Index = $i }
        }
    }
    return $scored | Sort-Object @{Expression='Score';Descending=$true}
}

function Get-EbbinghausRetention {
    <#
    .SYNOPSIS
      Calculates memory retention R(t) based on Ebbinghaus exponential decay
      with reinforcement half-life expansion:
        R(t) = exp( - delta_t / (tau * (1 + ln(1 + R_m))) )
    #>
    param(
        [datetime]$EntryDate,
        [int]$ReinforcementCount = 1,
        [double]$TauDays = 30.0,
        [datetime]$CurrentTime = (Get-Date)
    )
    $deltaDays = [Math]::Max(0.0, ($CurrentTime - $EntryDate).TotalDays)
    # Memory consolidation factor: each reinforcement expands stability
    $stability = $TauDays * (1.0 + [Math]::Log(1.0 + [Math]::Max(1, $ReinforcementCount)))
    $retention = [Math]::Exp(- ($deltaDays / $stability))
    return [Math]::Round([Math]::Max(0.01, [Math]::Min(1.0, $retention)), 4)
}

function Get-CognitiveActivationScore {
    <#
    .SYNOPSIS
      Computes multi-factor cognitive activation score A(m, Q, t):
        A = w_rel * BM25+ + w_rec * Retention + w_imp * SeverityWeight
    #>
    param(
        [double]$BM25Score,
        [double]$RetentionScore,
        [string]$Severity = 'medium',
        [double]$WeightRel = 0.60,
        [double]$WeightRec = 0.25,
        [double]$WeightImp = 0.15
    )
    $severityWeights = @{
        'critical' = 1.00
        'high'     = 0.90
        'medium'   = 0.70
        'low'      = 0.50
        'refactor' = 0.40
        'decision' = 0.80
        'pattern'  = 0.75
    }
    $imp = if ($severityWeights.ContainsKey($Severity.ToLower())) { $severityWeights[$Severity.ToLower()] } else { 0.60 }
    
    # Normalize BM25 score with tanh saturation to scale [0, 1]
    $normRel = [Math]::Tanh($BM25Score / 4.0)
    $activation = ($WeightRel * $normRel) + ($WeightRec * $RetentionScore) + ($WeightImp * $imp)
    return [Math]::Round($activation, 4)
}

# ═══════════════════════════════════════════════════════════════════════════════
# 3. INFORMATION THEORY: SHANNON ENTROPY & COMPRESSION BOUNDS
# ═══════════════════════════════════════════════════════════════════════════════

function Get-ShannonEntropy {
    <#
    .SYNOPSIS
      Calculates empirical Shannon entropy H(X) in bits per token.
        H(X) = - sum_{w in V} p(w) * log2(p(w))
    #>
    param([string]$Text)
    $tokens = Get-Tokens -Text $Text
    if ($tokens.Count -eq 0) { return 0.0 }
    
    $freq = @{}
    foreach ($t in $tokens) {
        if ($freq.ContainsKey($t)) { $freq[$t]++ } else { $freq[$t] = 1 }
    }
    
    $total = [double]$tokens.Count
    $entropy = 0.0
    foreach ($count in $freq.Values) {
        $p = [double]$count / $total
        $entropy -= $p * ([Math]::Log($p) / [Math]::Log(2.0))
    }
    return [Math]::Round($entropy, 4)
}

function Get-InformationDensity {
    <#
    .SYNOPSIS
      Calculates the Information Density Index (IDI): ratio of unique vocabulary
      and entropy against token length, measuring prompt compactness.
    #>
    param([string]$Text)
    $tokens = Get-Tokens -Text $Text
    if ($tokens.Count -eq 0) { return 0.0 }
    $uniqueCount = @($tokens | Select-Object -Unique).Count
    $entropy = Get-ShannonEntropy -Text $Text
    # IDI = (UniqueTokens / TotalTokens) * (Entropy / log2(TotalTokens + 1))
    $vocabRichness = $uniqueCount / [double]$tokens.Count
    $normEntropy = $entropy / [Math]::Max(1.0, ([Math]::Log($tokens.Count + 1) / [Math]::Log(2.0)))
    return [Math]::Round(($vocabRichness * $normEntropy), 4)
}

# ═══════════════════════════════════════════════════════════════════════════════
# 4. GRAPH THEORY: PERSONALIZED PAGERANK (POWER ITERATION)
# ═══════════════════════════════════════════════════════════════════════════════

function Invoke-PersonalizedPageRank {
    <#
    .SYNOPSIS
      Computes Stationary Distribution pi of a Directed Symbol Graph via Power Iteration:
        pi^(k+1) = (1 - alpha) * P^T * pi^(k) + alpha * v
      Guaranteed geometric convergence by Perron-Frobenius theorem.
    #>
    param(
        [hashtable]$AdjacencyList,      # Node -> Array of Outgoing Neighbor Nodes
        [hashtable]$Personalization,    # Node -> Initial Teleport Weight v (sum to 1)
        [double]$Alpha = 0.15,          # Damping / Teleport parameter
        [double]$Epsilon = 1e-6,        # Convergence threshold
        [int]$MaxIterations = 40
    )
    # Collect all unique nodes
    $nodeSet = @{}
    foreach ($k in $AdjacencyList.Keys) {
        $nodeSet[$k] = $true
        foreach ($dest in $AdjacencyList[$k]) { $nodeSet[$dest] = $true }
    }
    if ($null -ne $Personalization) {
        foreach ($k in $Personalization.Keys) { $nodeSet[$k] = $true }
    }

    $nodes = @($nodeSet.Keys)
    $nodeCount = $nodes.Count
    if ($nodeCount -eq 0) { return @{} }

    # Setup Personalization Vector v
    $v = @{}
    $vSum = 0.0
    if ($null -ne $Personalization -and $Personalization.Keys.Count -gt 0) {
        foreach ($n in $nodes) {
            $w = if ($Personalization.ContainsKey($n)) { [double]$Personalization[$n] } else { 0.0 }
            $v[$n] = $w
            $vSum += $w
        }
    }
    # Uniform fallback if personalization is empty or zero-sum
    if ($vSum -le 0.0) {
        $uniform = 1.0 / [double]$nodeCount
        foreach ($n in $nodes) { $v[$n] = $uniform }
    } else {
        foreach ($n in $nodes) { $v[$n] = $v[$n] / $vSum }
    }

    # Initialize pi^(0) = v
    $pi = @{}
    foreach ($n in $nodes) { $pi[$n] = $v[$n] }

    # Invert Adjacency for Incoming Edges P^T
    # incoming[j] = @( { node = i; outDegree = out_deg(i) } )
    $incoming = @{}
    $outDegree = @{}
    foreach ($n in $nodes) {
        $incoming[$n] = @()
        $out = if ($AdjacencyList.ContainsKey($n)) { @($AdjacencyList[$n]) } else { @() }
        $outDegree[$n] = $out.Count
    }
    foreach ($src in $AdjacencyList.Keys) {
        $deg = $outDegree[$src]
        if ($deg -gt 0) {
            foreach ($dst in $AdjacencyList[$src]) {
                if ($incoming.ContainsKey($dst)) {
                    $incoming[$dst] += [pscustomobject]@{ Source = $src; Degree = $deg }
                }
            }
        }
    }

    # Power Iteration Loop
    for ($iter = 0; $iter -lt $MaxIterations; $iter++) {
        $piNext = @{}
        $danglingWeight = 0.0

        # Calculate weight from dangling nodes (out-degree = 0)
        foreach ($n in $nodes) {
            if ($outDegree[$n] -eq 0) {
                $danglingWeight += $pi[$n]
            }
        }

        $l1Diff = 0.0
        foreach ($n in $nodes) {
            $rankFromIn = 0.0
            foreach ($edge in $incoming[$n]) {
                $rankFromIn += ($pi[$edge.Source] / [double]$edge.Degree)
            }
            # Matrix transition + dangling redistribution + teleportation
            $transition = $rankFromIn + ($danglingWeight / [double]$nodeCount)
            $newVal = ((1.0 - $Alpha) * $transition) + ($Alpha * $v[$n])
            $piNext[$n] = $newVal
            $l1Diff += [Math]::Abs($newVal - $pi[$n])
        }

        $pi = $piNext
        if ($l1Diff -lt $Epsilon) { break }
    }

    # Format result as rounded scores
    $result = @{}
    foreach ($n in $nodes) {
        $result[$n] = [Math]::Round($pi[$n], 6)
    }
    return $result
}
