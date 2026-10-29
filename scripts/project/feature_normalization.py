#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""内容库特征归一化：generate_questions.py 与 init_data.py 共用的唯一实现。"""

import numpy as np

# 10 维特征键名（与论文 Table 3 一致；顺序敏感，f6/f9 按索引 3/5 反转）
FEATURE_KEYS = [
    "f1_avg_sentence_length",   # d1
    "f3_sentence_count",        # d2
    "f5_function_word_ratio",   # d3
    "f6_avg_char_log_freq",     # d4
    "f8_tongjiazi_density",     # d5
    "f9_ppl_ancient",           # d6
    "f10_ppl_modern",           # d7
    "f11_mattr",                # d8
    "f12_allusion_density",     # d9
    "f13_semantic_complexity",  # d10
]


def percentile_normalize(features: dict, lower_pct: int = 2,
                         upper_pct: int = 98) -> dict:
    """把特征按 P2/P98 百分位裁剪并缩放到 [0,1]，返回同键的新字典。

    features: {title: {feature_key: value}}；缺少的特征键按 0.0 处理。
    空输入原样返回。常量特征（上下界相差不超过 1e-9）取 0.5。
    f6（索引 3）与 f9（索引 5）是“值越大越难”的反向特征，归一化后取 1-x。
    """
    if not features:
        return features

    titles = list(features.keys())
    n_features = len(FEATURE_KEYS)
    raw_matrix = np.zeros((len(titles), n_features))
    for i, title in enumerate(titles):
        for j, key in enumerate(FEATURE_KEYS):
            raw_matrix[i, j] = features[title].get(key, 0.0)

    lowers = np.percentile(raw_matrix, lower_pct, axis=0)
    uppers = np.percentile(raw_matrix, upper_pct, axis=0)

    normalized_matrix = np.zeros_like(raw_matrix)
    for j in range(n_features):
        if uppers[j] - lowers[j] > 1e-9:
            normalized_matrix[:, j] = np.clip(
                (raw_matrix[:, j] - lowers[j]) / (uppers[j] - lowers[j]), 0.0, 1.0
            )
        else:
            normalized_matrix[:, j] = 0.5

    normalized_matrix[:, 3] = 1 - normalized_matrix[:, 3]  # f6
    normalized_matrix[:, 5] = 1 - normalized_matrix[:, 5]  # f9

    return {
        title: {
            FEATURE_KEYS[j]: float(normalized_matrix[i, j])
            for j in range(n_features)
        }
        for i, title in enumerate(titles)
    }
