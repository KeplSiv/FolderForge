#!/usr/bin/env python3
"""Fill FolderForge .strings files from compiler-extracted SwiftUI keys.

Existing translations are preserved. Missing values are drafted through Google Translate's
public endpoint, with printf placeholders protected and made positional before translation.
"""

from __future__ import annotations

import json
import html
import os
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LOCALIZATIONS = ROOT / "Resources" / "Localizations"
STRINGSDATA_ROOT = Path("/tmp/FolderForgeDerivedData/Build/Intermediates.noindex")
CACHE_PATH = Path("/tmp/folderforge-translation-cache.json")
DELIMITER = "__FFSPLIT9A7C__"
BATCH_SIZE = 50

LANGUAGES = {
    "es": "es",
    "fr": "fr",
    "de": "de",
    "pt-BR": "pt",
    "it": "it",
    "nl": "nl",
    "pl": "pl",
    "ru": "ru",
    "uk": "uk",
    "tr": "tr",
    "zh-Hans": "zh-CN",
    "ja": "ja",
    "ko": "ko",
    "vi": "vi",
    "id": "id",
}

LANGUAGE_NAMES = {
    "ru": "Russian", "uk": "Ukrainian", "tr": "Turkish",
    "zh-CN": "Simplified Chinese", "ja": "Japanese", "ko": "Korean",
    "vi": "Vietnamese", "id": "Indonesian",
}

FORMAT_PATTERN = re.compile(
    r"%(?!%)(?:\d+\$)?[-+0 #]*(?:\d+|\*)?(?:\.\d+)?(?:hh|h|ll|l|L|z|j|t)?[@diuoxXfFeEgGaAcCsSp]"
)
STRINGS_LINE = re.compile(r'^\s*"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)";\s*$')
SWIFT_DYNAMIC_KEY = re.compile(
    r'(?:SectionLabel\(text:|LabeledSlider\(title:|Category\(name:|Group\(name:)\s*"((?:\\.|[^"\\])*)"'
)


def unescape_strings(value: str) -> str:
    return value.replace(r"\n", "\n").replace(r'\"', '"').replace(r"\\", "\\")


def escape_strings(value: str) -> str:
    return value.replace("\\", r"\\").replace('"', r'\"').replace("\n", r"\n")


def read_strings(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = STRINGS_LINE.match(line)
        if match:
            values[unescape_strings(match.group(1))] = unescape_strings(match.group(2))
    return values


def collect_keys() -> list[str]:
    keys: set[str] = set()
    for path in STRINGSDATA_ROOT.rglob("*.stringsdata"):
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        for entry in payload.get("tables", {}).get("Localizable", []):
            key = entry.get("key", "")
            if key:
                keys.add(key)

    # Keep dynamic keys that the compiler cannot see through LocalizedStringKey(String).
    for path in LOCALIZATIONS.glob("*.lproj/Localizable.strings"):
        keys.update(read_strings(path))
    for path in (ROOT / "Sources" / "FolderForge").rglob("*.swift"):
        source = path.read_text(encoding="utf-8")
        for match in SWIFT_DYNAMIC_KEY.finditer(source):
            keys.add(match.group(1).replace(r'\"', '"').replace(r"\\", "\\"))

    keys.update({
        "System", "Muted", "Vivid", "Deep", "Neutral",
        "Back", "Paper", "Front", "Fit", "Fill",
        "None", "Symbol", "Emoji", "Text", "App Icon",
        "Engraved", "Tinted", "Natural", "Stamped", "Raised",
        "Carved into the folder face. Matches Apple's own folder icons.",
        "A clean monochrome treatment in a color you pick.",
        "Keeps the artwork's own colors. Best for emoji and photos.",
        "Dark ink pressed into the folder.",
        "Bright and glossy, floating above the folder.",
        "Exact", "Contains", "Starts with", "Ends with", "Glob",
        "Folder name", "Relative path", "Marker file", "File type majority",
        "Objects", "Symbols", "Activity", "Places", "Nature", "Food", "People",
        "Favorites", "Work", "Files", "Media", "Design", "Code", "Life",
        "Travel", "Health", "Security", "Letters", "Numbers",
        "My Styles (0)", "Choose style",
    })
    return sorted(keys)


def positional_and_protected(text: str) -> tuple[str, dict[str, str]]:
    replacements: dict[str, str] = {}
    index = 0

    def replace(match: re.Match[str]) -> str:
        nonlocal index
        index += 1
        specifier = match.group(0)
        if not re.match(r"%\d+\$", specifier):
            specifier = f"%{index}$" + specifier[1:]
        token = f"__FFPH{index:03d}__"
        replacements[token] = specifier
        return token

    return FORMAT_PATTERN.sub(replace, text), replacements


def restore_placeholders(text: str, replacements: dict[str, str]) -> str:
    for token, specifier in replacements.items():
        text = text.replace(token, specifier)
    if any(token in text for token in replacements):
        raise ValueError("unrestored placeholder")
    return text


def translate_request(text: str, language: str) -> str:
    language_name = LANGUAGE_NAMES.get(language)
    if language_name is not None:
        prompt = (
            f"Translate the text inside each HTML paragraph from English to {language_name}. "
            f"Preserve every p tag, id attribute, FolderForge, Finder, macOS, GitHub, SF Symbols, "
            "file extension, keyboard shortcut, and token like __FFPH001__ exactly. "
            "Return only the translated HTML paragraphs in the same order.\n" + text
        )
        data = json.dumps({
            "model": "translategemma:4b",
            "prompt": prompt,
            "stream": False,
            "keep_alive": "30m",
            "options": {"temperature": 0, "num_predict": 8192, "num_ctx": 16384},
        }).encode("utf-8")
        request = urllib.request.Request(
            "http://127.0.0.1:11434/api/generate",
            data=data,
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(request, timeout=600) as response:
            payload = json.loads(response.read().decode("utf-8"))
        return payload["response"].strip()

    data = urllib.parse.urlencode({
        "client": "gtx", "sl": "en", "tl": language, "dt": "t", "q": text,
    }).encode("utf-8")
    request = urllib.request.Request(
        "https://translate.google.com/translate_a/single",
        data=data,
        headers={"User-Agent": "FolderForge-Localization/1.0"},
    )
    for attempt in range(5):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                payload = json.loads(response.read().decode("utf-8"))
            return "".join(segment[0] for segment in payload[0] if segment[0] is not None)
        except Exception as error:
            if attempt == 4:
                raise
            if getattr(error, "code", None) == 429:
                time.sleep(30)
            else:
                time.sleep(1.5 * (attempt + 1))
    raise RuntimeError("translation request failed")


def translate_batch(strings: list[str], language: str) -> list[str]:
    protected: list[str] = []
    replacements: list[dict[str, str]] = []
    for value in strings:
        safe, mapping = positional_and_protected(value)
        protected.append(safe)
        replacements.append(mapping)

    if language in LANGUAGE_NAMES:
        paragraphs = "".join(
            f'<p id="{index}">{html.escape(value)}</p>'
            for index, value in enumerate(protected)
        )
        translated = translate_request(paragraphs, language)
        matches = re.findall(r'<p\s+id=["\']?(\d+)["\']?[^>]*>(.*?)</p>', translated,
                             flags=re.IGNORECASE | re.DOTALL)
        found = {int(index): html.unescape(re.sub(r"<[^>]+>", "", value)).strip()
                 for index, value in matches}
        if len(found) != len(strings):
            if len(strings) == 1:
                raise ValueError(f"local model did not preserve paragraph: {translated[:200]}")
            midpoint = len(strings) // 2
            return (translate_batch(strings[:midpoint], language)
                    + translate_batch(strings[midpoint:], language))
        return [restore_placeholders(found[index], replacements[index])
                for index in range(len(strings))]

    joined = f"\n{DELIMITER}\n".join(protected)
    translated = translate_request(joined, language)
    pieces = re.split(rf"\s*{re.escape(DELIMITER)}\s*", translated)
    if len(pieces) != len(strings):
        if len(strings) == 1:
            raise ValueError(f"translation service changed separator: {translated[:200]}")
        midpoint = len(strings) // 2
        return (translate_batch(strings[:midpoint], language)
                + translate_batch(strings[midpoint:], language))
    return [restore_placeholders(piece.strip(), mapping)
            for piece, mapping in zip(pieces, replacements)]


def write_strings(path: Path, keys: list[str], translations: dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [f'"{escape_strings(key)}" = "{escape_strings(translations[key])}";' for key in keys]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_partial_strings(path: Path, translations: dict[str, str]) -> None:
    known_keys = sorted(translations)
    write_strings(path, known_keys, translations)


def main() -> None:
    keys = collect_keys()
    english_path = LOCALIZATIONS / "en.lproj" / "Localizable.strings"
    write_strings(english_path, keys, {key: key for key in keys})
    print(f"english: {len(keys)} keys")

    try:
        cache: dict[str, str] = json.loads(CACHE_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        cache = {}

    selected = {item for item in os.environ.get("FF_LOCALES", "").split(",") if item}
    for locale, target in LANGUAGES.items():
        if selected and locale not in selected:
            continue
        path = LOCALIZATIONS / f"{locale}.lproj" / "Localizable.strings"
        values = read_strings(path)
        missing = [key for key in keys if key not in values]
        for offset in range(0, len(missing), BATCH_SIZE):
            batch = missing[offset:offset + BATCH_SIZE]
            if target in LANGUAGE_NAMES:
                results = translate_batch(batch, target)
                for key, result in zip(batch, results):
                    values[key] = result
                write_partial_strings(path, values)
            else:
                uncached = [key for key in batch if f"{target}\0{key}" not in cache]
                if uncached:
                    results = translate_batch(uncached, target)
                    for key, result in zip(uncached, results):
                        cache[f"{target}\0{key}"] = result
                    CACHE_PATH.write_text(json.dumps(cache, ensure_ascii=False), encoding="utf-8")
                for key in batch:
                    values[key] = cache[f"{target}\0{key}"]
            print(f"{locale}: {min(offset + len(batch), len(missing))}/{len(missing)} missing keys", flush=True)
            time.sleep(0.08)
        write_strings(path, keys, values)
        print(f"{locale}: complete ({len(keys)} keys)", flush=True)


if __name__ == "__main__":
    main()
