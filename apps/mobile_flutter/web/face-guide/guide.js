// All detector code, WASM and model files are served by InterCity.
import {FaceDetector, FilesetResolver} from './vision_bundle.mjs';
let detector, timer, generation = 0, loading;
function videoElement(root=document) {
  const video = root.querySelector('video');
  if (video) return video;
  for (const e of root.querySelectorAll('*')) {
    if (e.shadowRoot) { const found=videoElement(e.shadowRoot); if(found) return found; }
  }
}
window.intercityFaceGuide = {
  async start(report) {
    this.stop(); const current=generation;
    try {
      loading ??= (async()=> {
        const files = await FilesetResolver.forVisionTasks(new URL('./wasm', import.meta.url).href);
        detector = await FaceDetector.createFromOptions(files, {
          baseOptions: {modelAssetPath:new URL('./blaze_face_short_range.tflite',import.meta.url).href, delegate:'CPU'},
          runningMode:'VIDEO', minDetectionConfidence:.65
        });
      })().catch(e=>{loading=undefined;throw e;});
      await loading;
      if(current!==generation) return;
      let lastTime=-1;
      timer=setInterval(()=> {
        if(current!==generation) return;
        const video=videoElement();
        if(!video || video.readyState<2 || !video.videoWidth || video.currentTime===lastTime) return;
        lastTime=video.currentTime;
        try {
          const result=detector.detectForVideo(video,performance.now());
          report(JSON.stringify({available:true, faces:result.detections.map(d=>({
            x:d.boundingBox.originX/video.videoWidth,y:d.boundingBox.originY/video.videoHeight,
            w:d.boundingBox.width/video.videoWidth,h:d.boundingBox.height/video.videoHeight
          }))}));
        } catch (_) { report(JSON.stringify({available:false,faces:[]})); }
      },350);
    } catch (_) { if(current===generation) report(JSON.stringify({available:false,faces:[]})); }
  },
  stop() { generation++; clearInterval(timer); timer=undefined; }
};
