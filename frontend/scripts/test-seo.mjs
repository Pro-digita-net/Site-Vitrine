import {readFile,access} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {pages,origin} from '../src/seo.js';
const root=new URL('../dist/',import.meta.url);
const titles=new Set();
for(const path of Object.keys(pages)){
 const html=await readFile(new URL(path==='/'?'index.html':path.slice(1)+'.html',root),'utf8');
 assert.equal((html.match(/<h1[\s>]/g)||[]).length,1,path+' doit avoir un H1');
 assert.equal((html.match(/rel="canonical"/g)||[]).length,1,path+' canonique unique');
 assert(html.includes('href="'+origin+path+'"'),path+' canonique correcte');
 assert(html.includes('property="og:title"'),path+' partage social');
 assert(!html.includes('noindex'),path+' indexable');
 const title=html.match(/<title>(.*?)<\/title>/s)?.[1];assert(title && !titles.has(title),path+' titre unique');titles.add(title);
 for(const [,url] of html.matchAll(/href="(\/[^"#?]*)(?:[?#][^"]*)?"/g)){
  if(url.startsWith('/assets/')||url==='/favicon.svg') await access(new URL(url.slice(1),root));
  else assert(pages[url],path+' lien interne inconnu '+url);
 }
 assert(!html.includes('href="/#/'),path+' anciennes adresses');
}
const missing=await readFile(new URL('404.html',root),'utf8');assert(missing.includes('noindex,follow'));
const sitemap=await readFile(new URL('sitemap.xml',root),'utf8');assert.equal((sitemap.match(/<loc>/g)||[]).length,Object.keys(pages).length);
console.log('SEO validé : '+titles.size+' pages, H1, titres uniques, canoniques, liens, partage, sitemap et 404.');
