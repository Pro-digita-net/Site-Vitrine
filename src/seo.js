import { products, formations, services, projects } from './data.js';
export const origin = 'https://pro-digital.net';
const base = [
 ['/', 'Création de sites web, conseil et assistance informatique', 'ProDigital accompagne les professionnels : création de sites internet, conseil informatique, assistance et formations numériques. Parlons de votre projet.'],
 ['/expertises', 'Création web, conseil et support informatique', 'Découvrez les expertises ProDigital : création de sites internet, conseil informatique, formation et assistance pour les professionnels.'],
 ['/formations', 'Formations web, bureautique et informatique', 'Découvrez nos formations WordPress, Excel, Microsoft 365, sécurité numérique et intelligence artificielle. Présentez-nous vos besoins.'],
 ['/solutions', 'Nos logiciels en préparation', 'Découvrez les logiciels en préparation chez ProDigital : CRM, assistance informatique, facturation et portail client.'],
 ['/projets', 'Projets et concepts web', 'Explorez nos concepts de sites et d’interfaces : portfolio architectural et espace de travail professionnel. Découvrez notre approche du design.'],
 ['/studio', 'Le studio ProDigital', 'Découvrez ProDigital et notre approche de la création web, du conseil et de l’accompagnement informatique des professionnels.'],
 ['/contact', 'Contact et demande de projet', 'Présentez votre projet à ProDigital : création de site internet, formation, conseil ou assistance informatique. Contactez notre équipe.'],
 ['/confidentialite', 'Confidentialité et données personnelles', 'Découvrez comment ProDigital utilise les informations du formulaire de contact et comment nous contacter à propos de vos données.'],
];
export const pages = Object.fromEntries(base.map(([path,title,description]) => [path,{title:title+' — ProDigital',description}]));
for (const [prefix,items] of [['expertises',services],['formations',formations],['solutions',products],['projets',projects]]) for (const item of items) pages['/'+prefix+'/'+item.id] = {title:item.name+(prefix==='formations'?' — Formation':prefix==='solutions'?' — Logiciel en préparation':prefix==='projets'?' — Concept web':'')+' — ProDigital',description:item.description};
export function metadata(path) { return pages[path.replace(/\/$/,'') || '/'] || {title:'Page introuvable — ProDigital',description:'Cette page n’existe pas. Retrouvez les expertises et les formations ProDigital.',noindex:true}; }
export function tags(path) {
 const m=metadata(path);
 return {description:m.description,robots:m.noindex?'noindex,follow':'index,follow,max-image-preview:large','twitter:card':'summary_large_image','twitter:title':m.title,'twitter:description':m.description,'twitter:image':origin+'/assets/photos/collaboration.jpg','og:title':m.title,'og:description':m.description,'og:url':origin+(path.replace(/\/$/,'')||'/'),'og:type':'website','og:locale':'fr_FR','og:site_name':'ProDigital','og:image':origin+'/assets/photos/collaboration.jpg','og:image:alt':'Espace de travail et collaboration professionnelle'};
}
export function updateMetadata(path) {
 document.title=metadata(path).title;
 const set=(selector,tag,attrs)=>{let el=document.head.querySelector(selector);if(!el){el=document.createElement(tag);document.head.append(el);}for(const [k,v] of Object.entries(attrs))el.setAttribute(k,v);};
 set('link[rel="canonical"]','link',{rel:'canonical',href:origin+(path.replace(/\/$/,'')||'/')});
 for(const [key,content] of Object.entries(tags(path))){const attr=key.startsWith('og:')?'property':'name';set('meta['+attr+'="'+key+'"]','meta',{[attr]:key,content});}
}
