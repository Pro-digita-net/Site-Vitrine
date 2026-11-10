import assert from 'node:assert/strict';
import { buildContactMessage, getContactQuestions, isKnownSubject, subjectGroups } from '../src/contactQuestions.js';

const subjects = subjectGroups.flatMap(group => group.items.map(item => item.name)).concat('Autre besoin');
for (const subject of subjects) {
  assert.ok(isKnownSubject(subject));
  const { fields } = getContactQuestions(subject);
  assert.equal(new Set(fields.map(field => field.id)).size, fields.length, `Duplicate field for ${subject}`);
  assert.ok(fields.filter(field => field.required).length <= 2);
  const answers = Object.fromEntries(fields.map(field => [field.id, field.options?.[0] || 'Réponse de test']));
  const message = buildContactMessage({ subject, given_name: ' Test ', family_name: ' Nom ', email: ' test@example.com ', company: '', message: ' Une demande précise. ' }, { ...answers, staleAnswer: 'DO_NOT_EXPORT' });
  assert.ok(message.includes(`Sujet : ${subject}`));
  for (const field of fields) assert.ok(message.includes(`${field.label} : ${answers[field.id]}`));
  assert.ok(!message.includes('DO_NOT_EXPORT'));
  assert.ok(message.includes('Entreprise : Non précisée'));
}
const form = { subject: 'Support IT', given_name: 'Test', family_name: 'Nom', email: 'test@example.com', company: '', message: 'Un besoin de support informatique.' };
const message = buildContactMessage(form, { projectType: 'Créer une boutique en ligne', supportNeed: 'Renforcer notre équipe informatique', environment: '   ' });
assert.ok(!message.includes('boutique'));
assert.ok(!message.includes('Équipements et logiciels à couvrir'));
assert.ok(message.includes('Renforcer notre équipe informatique'));
assert.deepEqual(getContactQuestions('Sujet inconnu').fields, []);
assert.equal(isKnownSubject('Sujet inconnu'), false);
assert.deepEqual(getContactQuestions('Support IT').fields.filter(field => field.required).map(field => field.id), ['supportNeed', 'teamSize']);
console.log(`${subjects.length} sujets vérifiés : questions, champs essentiels, export complet et exclusion des anciennes réponses.`);

// Premier choix du formulaire : expertises, deux familles, « Autre besoin ».
import { subjectTopics, topicItems, topicOf } from '../src/contactQuestions.js';
assert.deepEqual(subjectTopics, ['Création web', 'Conseil IT', 'Support IT', 'Formations', 'Logiciels', 'Autre besoin']);
assert.equal(topicItems('Support IT'), null);
for (const topic of ['Formations', 'Logiciels']) {
  const groups = topicItems(topic);
  const categories = groups.map(group => group.category);
  assert.deepEqual(categories, [...categories].sort((a, b) => a.localeCompare(b, 'fr')), `catégories triées (${topic})`);
  for (const group of groups) {
    assert.deepEqual(group.names, [...group.names].sort((a, b) => a.localeCompare(b, 'fr')), `noms triés (${group.category})`);
    for (const name of group.names) { assert.ok(isKnownSubject(name)); assert.equal(topicOf(name), topic); }
  }
}
assert.equal(topicItems('Formations').flatMap(group => group.names).length, subjectGroups[1].items.length);
assert.equal(topicItems('Logiciels').flatMap(group => group.names).length, subjectGroups[2].items.length);
assert.equal(topicOf('Genesis CRM'), 'Logiciels');
assert.equal(topicOf('Support IT'), 'Support IT');
assert.equal(topicOf('Sujet inconnu'), '');
console.log('Sujets en deux niveaux vérifiés : familles, tri par catégorie puis par nom.');

import { subjectTopicGroups } from '../src/contactQuestions.js';
assert.deepEqual(subjectTopicGroups.map(group => group.names), [['Création web', 'Conseil IT', 'Support IT'], ['Formations', 'Logiciels']]);
assert.deepEqual([...subjectTopicGroups.flatMap(group => group.names), 'Autre besoin'], subjectTopics);
