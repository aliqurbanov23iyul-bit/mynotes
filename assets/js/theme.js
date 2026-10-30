import './errors.js';
let theme='dark';try{theme=localStorage.getItem('astra-theme')==='light'?'light':'dark';}catch{}document.documentElement.dataset.theme=theme;
const meta=document.querySelector('meta[name="theme-color"]');if(meta)meta.content=theme==='dark'?'#0b1020':'#f5f6fb';
if(window.visualViewport){const adjust=()=>document.documentElement.style.setProperty('--visual-height',window.visualViewport.height+'px');window.visualViewport.addEventListener('resize',adjust);adjust();}

if('serviceWorker'in navigator)navigator.serviceWorker.register(new URL('../../service-worker.js',import.meta.url)).catch(()=>{});
