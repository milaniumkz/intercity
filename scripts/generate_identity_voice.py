"""Offline asset build: pip install piper-tts==1.4.1 (CPU).
Only generated WAVs ship with InterCity; the model never runs on a user's device.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import urllib.request
import wave
from piper import PiperVoice, SynthesisConfig

REVISION = 'e7229f7d33a10e145e109b886d661984201ac3c4'
BASE = f'https://huggingface.co/rhasspy/piper-voices/resolve/{REVISION}/ru/ru_RU/irina/medium/'
FILES = {
    'ru_RU-irina-medium.onnx': '8ff38212d23da300bbe3705c645e6e5b9475f0bfde01558eb17813e22acaaaaa',
    'ru_RU-irina-medium.onnx.json': 'c2ec28bb38e2b59e93b959b3e40348c1afebbd272f30fed5d41205d08e98a9d7',
}
TEXTS = {
    'prepare': 'Расположите лицо в овале. Свет должен падать на лицо. Держите телефон неподвижно.',
    'front': 'Смотрите прямо.',
    'TURN_LEFT': 'Слегка поверните голову налево.',
    'TURN_RIGHT': 'Слегка поверните голову направо.',
    'LOOK_UP': 'Поднимите подбородок.',
    'OPEN_MOUTH': 'Откройте рот.',
    'BLINK': 'Медленно моргните два раза.',
    'done': 'Готово. Проверяем запись.',
    'retry': 'Проверка не пройдена. Попробуйте ещё раз.',
    'ready': 'Смотрите прямо в камеру.',
}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--model-dir', required=True, type=Path)
    args = parser.parse_args()
    args.model_dir.mkdir(parents=True, exist_ok=True)
    for name, expected in FILES.items():
        path = args.model_dir / name
        if not path.exists():
            with urllib.request.urlopen(BASE + name, timeout=120) as response:
                path.write_bytes(response.read())
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise RuntimeError('Invalid voice model checksum: ' + name)
    root = Path(__file__).resolve().parents[1]
    out = root / 'apps/mobile_flutter/assets/sounds/identity'
    out.mkdir(parents=True, exist_ok=True)
    voice = PiperVoice.load(args.model_dir / 'ru_RU-irina-medium.onnx')
    config = SynthesisConfig(length_scale=1.05, noise_scale=.5, noise_w_scale=.6)
    clips = {}
    for cue, text in TEXTS.items():
        path = out / (cue + '.wav')
        with wave.open(str(path), 'wb') as wav:
            voice.synthesize_wav(text, wav, config)
        with wave.open(str(path), 'rb') as wav:
            duration = wav.getnframes() / wav.getframerate()
            if cue == 'front' and duration > 1.8:
                raise RuntimeError('Neutral instruction must finish within two seconds')
            if cue == 'ready' and duration > 2.9:
                raise RuntimeError('Ready instruction must finish before the countdown')
            if cue.isupper() and duration > 3.0:
                raise RuntimeError('Action instruction leaves too little time to react: ' + cue)
        clips[cue] = {'text': text, 'seconds': round(duration, 3), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
        print(cue, round(duration, 2))
    (root / 'docs/identity-voice.json').write_text(json.dumps({
        'voice': 'Piper ru_RU-irina-medium', 'gender': 'female', 'language': 'ru-RU',
        'repository': 'https://huggingface.co/rhasspy/piper-voices', 'revision': REVISION,
        'modelSha256': FILES, 'generator': 'piper-tts==1.4.1', 'lengthScale': 1.05,
        'runtime': 'Bundled audio only; no external speech service', 'clips': clips,
    }, ensure_ascii=False, indent=2) + '\n')

if __name__ == '__main__':
    main()
