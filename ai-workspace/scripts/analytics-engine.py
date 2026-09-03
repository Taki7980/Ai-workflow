import json
import math
import sys
import os
from collections import defaultdict, Counter
import re

def compute_jaccard(set1, set2):
    intersection = len(set1.intersection(set2))
    union = len(set1.union(set2))
    return intersection / union if union > 0 else 0.0

def act_r_activation(recalls, time_elapsed, decay=0.5):
    """
    Computes ACT-R base-level activation: B = ln( sum(t_j ^ -d) )
    We approximate assuming continuous power-law decay.
    """
    if recalls <= 0:
        return -math.inf
    # Simplified continuous power-law approximation
    return math.log(recalls * (math.pow(max(time_elapsed, 1), -decay)))

def analyze_entropy(text):
    counts = Counter(text)
    total = sum(counts.values())
    entropy = -sum((count / total) * math.log2(count / total) for count in counts.values())
    max_entropy = math.log2(len(counts)) if len(counts) > 0 else 1
    density = entropy / max_entropy if max_entropy > 0 else 0
    return entropy, density

def personalized_pagerank(adj, personalization, alpha=0.15, max_iter=40, tol=1e-6):
    nodes = list(adj.keys())
    for deps in adj.values():
        nodes.extend(deps)
    nodes = list(set(nodes))
    N = len(nodes)
    
    if N == 0:
        return {}

    p_sum = sum(personalization.values())
    if p_sum <= 0:
        v = {n: 1/N for n in nodes}
    else:
        v = {n: (personalization.get(n, 0)/p_sum) for n in nodes}

    pi = {n: v[n] for n in nodes}
    
    in_edges = defaultdict(list)
    out_deg = defaultdict(int)
    for u, deps in adj.items():
        out_deg[u] = len(deps)
        for d in deps:
            in_edges[d].append(u)

    for _ in range(max_iter):
        next_pi = {}
        dangling_weight = sum(pi[n] for n in nodes if out_deg[n] == 0)
        
        diff = 0
        for n in nodes:
            rank_in = sum(pi[src]/out_deg[src] for src in in_edges[n])
            trans = rank_in + dangling_weight / N
            new_val = (1 - alpha) * trans + alpha * v[n]
            next_pi[n] = new_val
            diff += abs(new_val - pi[n])
            
        pi = next_pi
        if diff < tol:
            break
            
    return pi

def bm25plus(query, corpus, k1=1.5, b=0.75, delta=1.0):
    # corpus: dict of id -> text
    docs = {k: re.findall(r'\w+', v.lower()) for k, v in corpus.items()}
    q_terms = re.findall(r'\w+', query.lower())
    
    if not docs:
        return {}
        
    avg_len = sum(len(d) for d in docs.values()) / len(docs)
    df = defaultdict(int)
    for d in docs.values():
        unique_terms = set(d)
        for t in unique_terms:
            df[t] += 1
            
    scores = {}
    N = len(docs)
    for doc_id, doc_tokens in docs.items():
        doc_len = len(doc_tokens)
        len_norm = 1.0 - b + b * (doc_len / max(1.0, avg_len))
        tf = Counter(doc_tokens)
        
        score = 0
        for q in q_terms:
            f = tf[q]
            if f <= 0:
                continue
            nq = df[q]
            idf = math.log(((N - nq + 0.5) / (nq + 0.5)) + 1.0)
            if idf < 0: idf = 0.01
            term_score = idf * (((f * (k1 + 1)) / (f + k1 * len_norm)) + delta)
            score += term_score
        scores[doc_id] = score
        
    return scores

if __name__ == "__main__":
    print("AI-Workflow Mathematical Analytics Engine")
    print("---------------------------------------")
    print("Ready to process metrics for CI/CD gates.")