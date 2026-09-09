#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
颜文字数据生成脚本
从 ekohrt/emoticon_kaomoji_dataset 下载 62,000 条颜文字数据，
清洗、去重、分类映射后生成结构化 JSON 文件供输入法使用。

用法: python generate_kaomoji.py
输出: ../../fcitx5-android/app/src/main/assets/kaomoji_data.json
"""

import json
import os
import sys
import urllib.request
from collections import defaultdict

# 数据源 URL
DATA_URL = "https://raw.githubusercontent.com/ekohrt/emoticon_kaomoji_dataset/main/emoticon_dict.json"

# 脚本所在目录
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
# 项目根目录
PROJECT_ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))
# 输出目录
OUTPUT_DIR = os.path.join(PROJECT_ROOT, "fcitx5-android", "app", "src", "main", "assets")
# 输出文件路径
OUTPUT_FILE = os.path.join(OUTPUT_DIR, "kaomoji_data.json")

# 数据集中 95 个 new_tags -> 中文分类映射
# 参考: https://github.com/ekohrt/emoticon_kaomoji_dataset
TAG_TO_CATEGORY = {
    # 开心/微笑类
    "smiling": "开心",
    "blush": "害羞",
    "excited": "激动",
    "sparkles": "闪光",
    "yummy": "美味",
    # 悲伤类
    "sad": "悲伤",
    "crying": "哭泣",
    "asleep": "困倦",
    "dead": "死亡",
    # 愤怒类
    "anger": "生气",
    "annoyed": "烦恼",
    "fight": "打架",
    # 爱心类
    "heart": "爱心",
    "kiss": "亲亲",
    "hug": "抱抱",
    "proposal": "求婚",
    # 动作类
    "dancing": "跳舞",
    "running": "奔跑",
    "salute_wave": "问候",
    "hello_message": "问候",
    "goodbye_message": "告别",
    "thanks_message": "感谢",
    "morning_night_evening_message": "问候",
    "flex": "肌肉",
    "pointing": "指方向",
    "thumbs_up": "点赞",
    "table_flip": "掀桌",
    "shrug": "摊手",
    "spinning": "旋转",
    "lying_down": "躺平",
    # 动物类
    "bear": "熊",
    "koala": "考拉",
    "cat": "猫",
    "dog": "狗",
    "bird": "鸟",
    "fish": "鱼",
    "rabbit": "兔子",
    "frog": "青蛙",
    "monkey": "猴子",
    "mouse": "老鼠",
    "pig": "猪",
    "hamster": "仓鼠",
    "sheep": "羊",
    "seal": "海豹",
    "spider": "蜘蛛",
    "butterfly": "蝴蝶",
    # 物品类
    "flower": "花朵",
    "rose": "玫瑰",
    "food": "食物",
    "music": "音乐",
    "glasses": "眼镜",
    "monocle": "单片眼镜",
    "mustache": "胡子",
    "gun": "武器",
    "sword": "剑",
    "wand": "魔杖",
    "bomb": "炸弹",
    "cigarette": "抽烟",
    "crown": "皇冠",
    "money": "金钱",
    # 角色类
    "angel": "天使",
    "devil": "恶魔",
    "robot": "机器人",
    "zombie": "僵尸",
    "clown": "小丑",
    "ghost": "幽灵",
    "bats_vampires": "吸血鬼",
    # 表情类
    "lenny": "Lenny",
    "donger": "Donger",
    "surprised": "惊讶",
    "sweat": "流汗",
    "wink": "眨眼",
    "smirk": "坏笑",
    "middle finger": "中指",
    # 活动/场景类
    "cheerleader": "拉拉队",
    "soccer": "足球",
    "football": "橄榄球",
    "basketball": "篮球",
    "archery": "射箭",
    "chess": "国际象棋",
    "ping_pong": "乒乓球",
    "beach": "海滩",
    "wall": "墙",
    "computers": "电脑",
    "radio": "收音机",
    "writing": "写字",
    "christmas": "圣诞",
    "birthday": "生日",
    # 身体类
    "breasts": "胸部",
    "butt": "屁股",
    "penis": "男性",
}

# 颜文字长度过滤：太短的不是颜文字（如单个字符），太长的难以显示
MIN_LENGTH = 2
MAX_LENGTH = 30

# 每个分类最多保留的颜文字数量
MAX_PER_CATEGORY = 300


def download_data(url):
    """下载 JSON 数据"""
    print(f"正在下载数据: {url}")
    req = urllib.request.Request(url, headers={"User-Agent": "MemeBoard/1.0"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    print(f"下载完成，共 {len(data)} 条记录")
    return data


def is_valid_kaomoji(text):
    """判断是否为有效的颜文字"""
    if not text or len(text) < MIN_LENGTH or len(text) > MAX_LENGTH:
        return False
    # 过滤掉含 Unicode emoji 的（颜文字应该是纯文本符号）
    for ch in text:
        cp = ord(ch)
        # 过滤常见 emoji 范围 (U+1F000-U+1FAFF, U+1F300-U+1F9FF)
        if 0x1F000 <= cp <= 0x1FAFF:
            return False
        # 过滤 variation selector 和 ZWJ
        if cp in (0xFE0F, 0x200D, 0x20E3):
            return False
    # 过滤掉太简单的
    if text in ("-", "_", ".", ",", "!", "?", "+", "*", "#", "@"):
        return False
    return True


def get_category(new_tags, original_tags):
    """根据标签获取中文分类"""
    # 优先使用 new_tags（手动标注的质量更高）
    all_tags = (new_tags or []) + (original_tags or [])
    
    for tag in all_tags:
        tag_lower = tag.lower().strip()
        if tag_lower in TAG_TO_CATEGORY:
            return TAG_TO_CATEGORY[tag_lower]
    
    # 尝试从 original_tags 中提取关键词匹配
    for tag in (original_tags or []):
        tag_lower = tag.lower().strip()
        # 模糊匹配
        if "happy" in tag_lower or "smile" in tag_lower or "joy" in tag_lower:
            return "开心"
        if "sad" in tag_lower:
            return "悲伤"
        if "cry" in tag_lower or "tear" in tag_lower:
            return "哭泣"
        if "angry" in tag_lower or "anger" in tag_lower or "mad" in tag_lower:
            return "生气"
        if "love" in tag_lower or "heart" in tag_lower:
            return "爱心"
        if "kiss" in tag_lower:
            return "亲亲"
        if "hug" in tag_lower:
            return "抱抱"
        if "dance" in tag_lower:
            return "跳舞"
        if "run" in tag_lower:
            return "奔跑"
        if "wave" in tag_lower or "hello" in tag_lower or "hi " in tag_lower:
            return "问候"
        if "wink" in tag_lower:
            return "眨眼"
        if "surprise" in tag_lower or "shock" in tag_lower:
            return "惊讶"
        if "sleep" in tag_lower:
            return "困倦"
        if "bear" in tag_lower or "koala" in tag_lower:
            return "熊"
        if "cat" in tag_lower:
            return "猫"
        if "dog" in tag_lower:
            return "狗"
        if "flower" in tag_lower:
            return "花朵"
        if "music" in tag_lower or "sing" in tag_lower:
            return "音乐"
        if "gun" in tag_lower or "weapon" in tag_lower or "shoot" in tag_lower:
            return "武器"
        if "robot" in tag_lower:
            return "机器人"
        if "ghost" in tag_lower:
            return "幽灵"
        if "angel" in tag_lower:
            return "天使"
        if "devil" in tag_lower or "demon" in tag_lower:
            return "恶魔"
        if "zombie" in tag_lower or "dead" in tag_lower:
            return "僵尸"
        if "lenny" in tag_lower:
            return "Lenny"
    
    return None


def process_data(raw_data):
    """处理原始数据：清洗、分类、去重"""
    # 按分类组织
    categorized = defaultdict(list)
    # 全局去重
    seen = set()
    # 未分类的
    uncategorized = []
    
    for face, info in raw_data.items():
        face = face.strip()
        if not is_valid_kaomoji(face):
            continue
        if face in seen:
            continue
        seen.add(face)
        
        new_tags = info.get("new_tags", [])
        original_tags = info.get("original_tags", [])
        
        category = get_category(new_tags, original_tags)
        if category:
            categorized[category].append(face)
        else:
            uncategorized.append(face)
    
    # 限制每个分类的数量
    for cat in categorized:
        if len(categorized[cat]) > MAX_PER_CATEGORY:
            categorized[cat] = categorized[cat][:MAX_PER_CATEGORY]
    
    # 未分类的放入"其他"
    if uncategorized:
        categorized["其他"] = uncategorized[:MAX_PER_CATEGORY]
    
    return categorized


def generate_output(categorized):
    """生成输出 JSON"""
    # 分类顺序：按颜文字数量从多到少
    sorted_cats = sorted(categorized.items(), key=lambda x: len(x[1]), reverse=True)
    
    # 构建输出结构
    categories = []
    for cat_name, items in sorted_cats:
        if not items:
            continue
        # 取第一个颜文字作为分类预览
        preview = items[0] if items else ""
        categories.append({
            "name": cat_name,
            "preview": preview,
            "items": items
        })
    
    # 构建搜索索引：颜文字 -> 分类列表
    search_index = {}
    for cat in categories:
        for item in cat["items"]:
            if item not in search_index:
                search_index[item] = []
            search_index[item].append(cat["name"])
    
    output = {
        "version": 1,
        "source": "ekohrt/emoticon_kaomoji_dataset",
        "total_count": sum(len(c["items"]) for c in categories),
        "category_count": len(categories),
        "categories": categories,
        "search_index": search_index
    }
    
    return output


def main():
    # 1. 下载数据
    raw_data = download_data(DATA_URL)
    
    # 2. 处理数据
    print("正在处理数据...")
    categorized = process_data(raw_data)
    
    # 3. 生成输出
    print("正在生成输出...")
    output = generate_output(categorized)
    
    # 4. 确保输出目录存在
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    # 5. 写入文件
    print(f"正在写入文件: {OUTPUT_FILE}")
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)
    
    # 统计
    print(f"\n=== 生成完成 ===")
    print(f"总颜文字数: {output['total_count']}")
    print(f"分类数: {output['category_count']}")
    print(f"分类列表:")
    for cat in output["categories"]:
        print(f"  {cat['name']}: {len(cat['items'])} 个")
    print(f"输出文件: {OUTPUT_FILE}")


if __name__ == "__main__":
    main()
