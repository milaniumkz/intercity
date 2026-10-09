# Install edge-tts in a temporary virtual environment; this is build-time generation only.
import asyncio,json,os
from pathlib import Path
import edge_tts
root=Path(__file__).resolve().parents[1]/'apps/mobile_flutter'
phrases={
 'ru':{'left':'Поверните налево','right':'Поверните направо','uturn':'Выполните разворот','straight':'Продолжайте движение прямо','roundabout':'Следуйте по круговому движению','arrival':'Вы прибыли','payment_fallback':'Не удалось списать оплату с карты. Способ оплаты переведён на наличные.'},
 'kk':{'left':'Солға бұрылыңыз','right':'Оңға бұрылыңыз','uturn':'Кері бұрылыңыз','straight':'Тура жүріңіз','roundabout':'Айналма жолмен жүріңіз','arrival':'Сіз келдіңіз','payment_fallback':'Картадан төлем алынбады. Төлем әдісі қолма-қол ақшаға ауыстырылды.'}}
voices={'ru':'ru-RU-SvetlanaNeural','kk':'kk-KZ-AigulNeural'}
async def main():
 semaphore=asyncio.Semaphore(2);catalog={};manifest=[]
 async def create(lang,key,distance,text):
  name=f'{lang}_{key}_{distance}.mp3';path=root/'web/navigation-voice'/name
  async with semaphore:
   for attempt in range(3):
    try:
     await edge_tts.Communicate(text,voices[lang],rate='-5%',proxy=os.environ.get('HTTPS_PROXY')).save(str(path))
     if path.stat().st_size<1000:raise RuntimeError('Empty voice recording')
     break
    except Exception:
     if attempt==2:raise
     await asyncio.sleep(1)
  catalog[text]=f'navigation-voice/{name}';manifest.append({'file':name,'language':lang,'voice':voices[lang],'text':text})
 jobs=[]
 for lang,actions in phrases.items():
  for key,action in actions.items():
   for distance in ([0] if key in ('arrival','payment_fallback') else [50,100,300]):
    text=action if distance<=50 else (f'Через {distance} метров {action[0].lower()}{action[1:]}' if lang=='ru' else f'{distance} метрден кейін {action[0].lower()}{action[1:]}')
    jobs.append(create(lang,key,distance,text))
 await asyncio.gather(*jobs)
 (root/'web/navigation-voice/manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
 lines=[f'  {json.dumps(text,ensure_ascii=False)}: {json.dumps(path)},' for text,path in sorted(catalog.items())]
 (root/'lib/core/services/navigation_voice_catalog.dart').write_text('// Female navigation recordings: Svetlana (ru), Aigul (kk).\nconst navigationVoiceRecordings = <String, String>{\n'+'\n'.join(lines)+'\n};\n')
 print(f'Generated {len(manifest)} female navigation recordings')
asyncio.run(main())
