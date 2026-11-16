import { createServer } from 'vite';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { pages, origin, metadata, tags } from '../src/seo.js';
const escape = s => String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const template=await readFile('dist/index.html','utf8');
const server=await createServer({server:{middlewareMode:true},appType:'custom'});
try {
 const {render}=await server.ssrLoadModule('/src/entry-server.jsx');
 for(const path of [...Object.keys(pages),'/404']) {
  const m=metadata(path);
  const head='<title>'+escape(m.title)+'</title>\n<link rel="canonical" href="'+origin+path+'">\n'+Object.entries(tags(path)).map(([k,v])=>'<meta '+(k.startsWith('og:')?'property':'name')+'="'+k+'" content="'+escape(v)+'">').join('\n');
  const html=template.replace(/<title>[\s\S]*?<\/title>/,'').replace(/<meta\s+name="description"[\s\S]*?\/>/,'').replace('</head>',head+'\n</head>').replace('<div id="root"></div>','<div id="root">'+render(path)+'</div>');
  const target=path==='/'?'dist/index.html':path==='/404'?'dist/404.html':'dist'+path+'.html';
  await mkdir(target.slice(0,target.lastIndexOf('/')),{recursive:true}); await writeFile(target,html);
 }
 await writeFile('dist/sitemap.xml','<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'+Object.keys(pages).map(p=>'<url><loc>'+origin+p+'</loc></url>').join('')+'</urlset>');
 await writeFile('dist/robots.txt','User-agent: *\nAllow: /\nDisallow: /api/\nSitemap: '+origin+'/sitemap.xml\n');
 console.log('SEO : '+Object.keys(pages).length+' pages HTML, sitemap et robots générés.');
} finally { await server.close(); }
