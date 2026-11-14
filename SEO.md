# Référencement du site

Le build génère 29 pages HTML complètes à partir des composants React et des données du site. Les métadonnées sont centralisées dans src/seo.js. Toute nouvelle route doit être ajoutée à ce registre ; les pages de détail suivent automatiquement les catalogues.

Commandes : npm run build puis npm run test:seo.

Le déploiement doit utiliser le Dockerfile et la configuration Nginx mis à jour ensemble : routes sans fragment, pages HTML pré-rendues, erreurs HTTP 404, domaine canonique https://pro-digital.net. Les anciens liens /#/… sont repris côté navigateur, car le fragment n’est jamais transmis au serveur.

Les titres, descriptions, canoniques, Open Graph et cartes sociales sont présents dans chaque HTML et actualisés lors de la navigation. Le footer décrit ProDigital avec les microdonnées Organization. Les logiciels sont présentés comme étant en préparation et les projets comme des concepts, sans inventer de clients ni d’avis.

Après déploiement : vérifier les réponses HTTP de /, /expertises/creation-web, /sitemap.xml et d’une adresse inexistante ; vérifier la redirection www vers le domaine principal. Déclarer https://pro-digital.net/sitemap.xml dans Google Search Console et Bing Webmaster Tools avec le compte propriétaire. Contrôler l’indexation, les requêtes et les performances mobiles sur les pages réelles. L’indexation et le classement restent décidés par les moteurs.

Le test SEO contrôle les H1, titres uniques, canoniques, liens internes, métadonnées sociales, sitemap et exclusion de la page 404. Il ne remplace pas les mesures de performance et les tests navigateur sur le déploiement.

Références : https://developers.google.com/search/docs/crawling-indexing/javascript/javascript-seo-basics et https://developers.google.com/search/docs/crawling-indexing/sitemaps/build-sitemap
