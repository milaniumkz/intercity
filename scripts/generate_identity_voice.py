# Offline build helper: pip install espeakng-loader==0.2.4. No TTS service is used at runtime.
import ctypes,wave
from pathlib import Path
import espeakng_loader
lib=espeakng_loader.load_library()
lib.espeak_Initialize.argtypes=[ctypes.c_int,ctypes.c_int,ctypes.c_char_p,ctypes.c_int]
rate=lib.espeak_Initialize(2,0,str(Path(espeakng_loader.get_data_path()).parent).encode(),0)
if rate<8000:raise RuntimeError('Voice initialization failed')
if lib.espeak_SetVoiceByName(b'ru') != 0: raise RuntimeError('Russian voice is unavailable')
lib.espeak_SetParameter(1,175,0)
CALL=ctypes.CFUNCTYPE(ctypes.c_int,ctypes.POINTER(ctypes.c_short),ctypes.c_int,ctypes.c_void_p)
parts=[]
@CALL
def output(data,n,events):
 if n>0:parts.append(ctypes.string_at(data,n*2))
 return 0
lib.espeak_SetSynthCallback(output)
texts={'prepare':'Расположите лицо в овале. Включите свет перед собой. Снимите тёмные очки. Держите телефон неподвижно.', 'front':'Смотрите прямо.', 'TURN_LEFT':'Слегка поверните голову налево.', 'TURN_RIGHT':'Слегка поверните голову направо.', 'LOOK_UP':'Поднимите подбородок.', 'OPEN_MOUTH':'Откройте рот.', 'BLINK':'Медленно моргните два раза.', 'done':'Готово. Проверяем запись.', 'retry':'Проверка не пройдена. Можно попробовать ещё раз.', 'ready':'Смотрите прямо. Сейчас начнётся запись.'}
root=Path(__file__).resolve().parents[1]/'apps/mobile_flutter/assets/sounds/identity'
root.mkdir(parents=True,exist_ok=True)
for key,text in texts.items():
 parts.clear();data=text.encode()+b'\0';lib.espeak_Synth(data,len(data),0,0,0,1,None,None);lib.espeak_Synchronize()
 with wave.open(str(root/(key+'.wav')),'wb') as w:w.setnchannels(1);w.setsampwidth(2);w.setframerate(rate);w.writeframes(b''.join(parts))
 print(key,round(sum(map(len,parts))/2/rate,2))
lib.espeak_Terminate()
