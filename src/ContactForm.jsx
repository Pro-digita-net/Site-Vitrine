import React, { useRef, useState } from "react";
import { ArrowUpRight, Check, CircleAlert, Download, Mail, Plus } from "lucide-react";
import { contactEmail } from "./data.js";
import { buildContactMessage, getContactQuestions, isKnownSubject, subjectTopicGroups, topicItems, topicOf } from "./contactQuestions.js";

const ENDPOINT = "/api/contact-requests";
const EMPTY = { given_name: "", family_name: "", email: "", company: "", subject: "", message: "" };
// Clé d'envoi : identique tant que le contenu ne change pas, pour qu'un double
// clic ou un renvoi après coupure réseau ne crée jamais deux demandes.
const newKey = () => (crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}-${Math.random().toString(36).slice(2)}`);

// Titre d'étape, dans le style des intertitres du site (numéro bleu, filet, capitales).
function StepTitle({ number, children, as: Tag = "p" }) {
  return <Tag className="form-step-title"><span aria-hidden="true">{number}</span><i aria-hidden="true" />{children}</Tag>;
}

// Une réponse courte (liste aux choix brefs, téléphone) peut partager une ligne avec une autre.
const isShort = (field) => field.type === "tel" || (field.type === "select" && field.options.every(option => option.length <= 26));
// Deux réponses courtes consécutives vont côte à côte ; tout le reste prend la largeur.
function withLayout(fields) {
  const wide = fields.map(() => true);
  for (let i = 0; i < fields.length; i += 1) {
    if (isShort(fields[i]) && fields[i + 1] && isShort(fields[i + 1])) { wide[i] = wide[i + 1] = false; i += 1; }
    else if (isShort(fields[i]) && i === fields.length - 1) wide[i] = false;
  }
  return fields.map((field, i) => ({ field, wide: wide[i] }));
}
// Espace insécable avant ? : ! — la ponctuation ne passe jamais seule à la ligne.
const typo = (text) => text.replace(/ ([?:!])/g, " $1");

function Question({ field, value, onChange, disabled, hideOptionalTag = false, wide = false }) {
  const props = {
    id: `request-${field.id}`,
    name: field.id,
    value: value || "",
    required: field.required,
    onChange,
    disabled,
  };
  return (
    <label htmlFor={props.id} className={wide ? "wide" : undefined}>
      <span className="field-label">{typo(field.label)}{field.required ? <span className="required" aria-hidden="true"> *</span> : !hideOptionalTag && <small> (facultatif)</small>}</span>
      {field.type === "select" ? (
        <select {...props} data-empty={props.value ? undefined : ""}>
          <option value="">Choisir une réponse</option>
          {field.options.map(option => <option key={option}>{option}</option>)}
        </select>
      ) : (
        <input {...props} type={field.type} placeholder={field.placeholder} maxLength={400} />
      )}
    </label>
  );
}

export default function ContactForm({ initialSubject = "" }) {
  const [form, setForm] = useState({ ...EMPTY, subject: isKnownSubject(initialSubject) ? initialSubject : "" });
  // Premier choix (expertise, « Formations », « Logiciels »…) ; `form.subject` reste le sujet précis.
  const [topic, setTopic] = useState(topicOf(initialSubject));
  const family = topicItems(topic); // catégories → noms, si le premier choix est une famille
  // Keep each subject's draft separately; only the selected subject is exported.
  const [drafts, setDrafts] = useState({});
  const [website, setWebsite] = useState(""); // champ piège anti-robots, invisible
  // idle | sending | sent | invalid | unavailable
  const [status, setStatus] = useState("idle");
  const [feedback, setFeedback] = useState({ message: "", errors: [] });
  const [receipt, setReceipt] = useState(null);
  const [copyStatus, setCopyStatus] = useState("");
  const keyRef = useRef(newKey());
  const sendingRef = useRef(false);
  const resultRef = useRef(null);

  const schema = getContactQuestions(form.subject);
  const answers = drafts[form.subject] || {};
  const requiredFields = schema.fields.filter(field => field.required);
  const optionalFields = schema.fields.filter(field => !field.required);
  const sending = status === "sending";
  const message = buildContactMessage(form, answers);
  const emailHref = `mailto:${contactEmail}?subject=${encodeURIComponent(`Projet ProDigital — ${form.subject || "Premier échange"}`)}&body=${encodeURIComponent(message)}`;

  const edited = () => {
    keyRef.current = newKey();
    setCopyStatus("");
    if (status !== "idle") { setStatus("idle"); setFeedback({ message: "", errors: [] }); }
  };
  const update = (event) => {
    const { name, value } = event.target;
    event.target.setCustomValidity("");
    setForm(previous => ({ ...previous, [name]: value }));
    edited();
  };
  const updateTopic = (event) => {
    const { value } = event.target;
    event.target.setCustomValidity("");
    setTopic(value);
    // Une famille attend le choix précis dans la seconde liste ; sinon le choix est le sujet.
    setForm(previous => ({ ...previous, subject: topicItems(value) ? "" : value }));
    edited();
  };
  const updateAnswer = (event) => {
    const { name, value } = event.target;
    event.target.setCustomValidity("");
    setDrafts(previous => ({ ...previous, [form.subject]: { ...previous[form.subject], [name]: value } }));
    edited();
  };
  const focusResult = () => requestAnimationFrame(() => resultRef.current?.focus());

  const send = async () => {
    if (sendingRef.current) return; // double soumission
    sendingRef.current = true;
    setStatus("sending");
    setFeedback({ message: "", errors: [] });
    try {
      const response = await fetch(ENDPOINT, {
        method: "POST",
        headers: { "Content-Type": "application/json", "Idempotency-Key": keyRef.current },
        body: JSON.stringify({ ...form, answers, website }),
        signal: AbortSignal.timeout(20000),
      });
      const data = await response.json().catch(() => ({}));
      // La confirmation n'apparaît que si le serveur atteste l'enregistrement.
      if ((response.status === 201 || response.status === 200) && data.id) {
        setReceipt({ id: data.id, email: form.email.trim(), name: form.given_name.trim() });
        setStatus("sent");
      } else if (response.status === 400 || response.status === 409 || response.status === 429) {
        setFeedback({ message: data.message || "Certaines informations sont à vérifier.", errors: data.errors || [] });
        setStatus("invalid");
        if (response.status === 409) keyRef.current = newKey();
      } else {
        setStatus("unavailable");
      }
    } catch {
      setStatus("unavailable");
    } finally {
      sendingRef.current = false;
      focusResult();
    }
  };

  const submit = (event) => {
    event.preventDefault();
    for (const input of event.currentTarget.elements) {
      if (input.required && typeof input.value === "string") {
        const minimum = input.name === "message" ? 10 : 1;
        input.setCustomValidity(input.value.trim().length < minimum
          ? (minimum === 10 ? "Décrivez votre demande en au moins 10 caractères." : "Merci de renseigner ce champ.") : "");
      }
    }
    if (!event.currentTarget.reportValidity()) return;
    void send();
  };
  const restart = () => {
    setForm(EMPTY);
    setDrafts({});
    setTopic("");
    setReceipt(null);
    setStatus("idle");
    keyRef.current = newKey();
  };
  const download = () => {
    const url = URL.createObjectURL(new Blob([message], { type: "text/plain;charset=utf-8" }));
    const link = document.createElement("a");
    link.href = url;
    link.download = "mon-projet-prodigital.txt";
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  };
  const copy = async () => {
    try {
      await navigator.clipboard.writeText(message);
      setCopyStatus("Message copié. Collez-le dans un e-mail à " + contactEmail + ".");
    } catch {
      setCopyStatus("La copie n’est pas disponible. Vous pouvez télécharger le message ou le sélectionner dans l’aperçu.");
    }
  };

  if (status === "sent" && receipt) {
    return (
      <div className="contact-form">
        <section className="prepared contact-sent" aria-labelledby="sent-heading" role="status">
          <Check aria-hidden="true" />
          <div>
            <h2 id="sent-heading" ref={resultRef} tabIndex={-1}>Votre demande est bien enregistrée.</h2>
            <p>Merci {receipt.name}. Nous l’avons reçue et nous vous répondrons à l’adresse {receipt.email}.</p>
            <p className="contact-reference">Référence de votre demande<br /><code>{receipt.id}</code></p>
            <button type="button" className="download-link" onClick={restart}>Envoyer une autre demande</button>
          </div>
        </section>
      </div>
    );
  }

  return (
    <form className="contact-form" onSubmit={submit} aria-busy={sending}>
      <h2>Parlons de votre projet.</h2>
      <p className="form-intro">Choisissez un sujet : les questions s’adaptent à votre demande. Les champs marqués <span className="required">*</span> sont obligatoires.</p>
      <section className="form-step">
      <StepTitle number="01">Vos coordonnées</StepTitle>
      <div className="form-row">
        <label><span className="field-label">Votre prénom <span className="required" aria-hidden="true">*</span></span><input name="given_name" autoComplete="given-name" value={form.given_name} onChange={update} required maxLength={80} disabled={sending} /></label>
        <label><span className="field-label">Votre nom <span className="required" aria-hidden="true">*</span></span><input name="family_name" autoComplete="family-name" value={form.family_name} onChange={update} required maxLength={80} disabled={sending} /></label>
      </div>
      <div className="form-row">
        <label><span className="field-label">Votre entreprise <small>(facultatif)</small></span><input name="company" autoComplete="organization" value={form.company} onChange={update} maxLength={150} disabled={sending} /></label>
        <label><span className="field-label">Votre e-mail <span className="required" aria-hidden="true">*</span></span><input type="email" name="email" autoComplete="email" value={form.email} onChange={update} required maxLength={200} disabled={sending} /></label>
      </div>
      </section>
      <div className="contact-trap" aria-hidden="true">
        <label>Ne pas remplir ce champ<input name="website" tabIndex={-1} autoComplete="off" value={website} onChange={event => setWebsite(event.target.value)} /></label>
      </div>
      <section className="form-step">
      <StepTitle number="02">Votre sujet</StepTitle>
      <label><span className="field-label">De quoi souhaitez-vous parler ? <span className="required" aria-hidden="true">*</span></span>
        <select name="topic" value={topic} onChange={updateTopic} required aria-describedby="subject-help" disabled={sending} data-empty={topic ? undefined : ""}>
          <option value="">Choisir un sujet</option>
          {subjectTopicGroups.map(group => <optgroup key={group.label} label={group.label}>{group.names.map(name => <option key={name}>{name}</option>)}</optgroup>)}
          <hr />
          <option>Autre besoin</option>
        </select>
      </label>
      {family && <label className="contact-subject-detail" key={topic}><span className="field-label">{topic === "Formations" ? "Quelle formation vous intéresse ?" : "Quel logiciel vous intéresse ?"} <span className="required" aria-hidden="true">*</span></span>
        <select name="subject" value={form.subject} onChange={update} required aria-describedby="subject-help" disabled={sending} data-empty={form.subject ? undefined : ""}>
          <option value="">{topic === "Formations" ? "Choisir une formation" : "Choisir un logiciel"}</option>
          {family.map(group => <optgroup key={group.category} label={group.category}>{group.names.map(name => <option key={name}>{name}</option>)}</optgroup>)}
        </select>
      </label>}
      <p className="contact-question-help" id="subject-help" role="status">
        {form.subject ? (requiredFields.length ? `${requiredFields.length} question${requiredFields.length > 1 ? "s" : ""} essentielle${requiredFields.length > 1 ? "s" : ""} ci-dessous, le reste est facultatif.` : "Les précisions ci-dessous sont facultatives.") : family ? (topic === "Formations" ? "Les formations sont classées par thème. Choisissez celle qui vous intéresse pour afficher les questions." : "Les logiciels sont classés par usage. Choisissez celui qui vous intéresse pour afficher les questions.") : "Vous hésitez ? Choisissez « Autre besoin » et expliquez votre situation."}
      </p>
      </section>
      {form.subject && <fieldset className="form-step contact-questions" key={form.subject}>
        <StepTitle number="03" as="legend">{schema.title}</StepTitle>
        <p className="contact-question-help">{schema.hint}</p>
        {requiredFields.map(field => <Question key={field.id} field={field} value={answers[field.id]} onChange={updateAnswer} disabled={sending} />)}
        {!!optionalFields.length && <details className="contact-optional">
          <summary><Plus size={16} aria-hidden="true" /><span className="contact-optional-title">Ajouter des précisions<small>Facultatif · {optionalFields.length} question{optionalFields.length > 1 ? "s" : ""}</small></span></summary>
          <p className="contact-question-help">Renseignez ce que vous savez déjà : nous préparerons un échange plus utile.</p>
          <div className="contact-optional-grid">
            {withLayout(optionalFields).map(({ field, wide }) => <Question key={field.id} field={field} wide={wide} value={answers[field.id]} onChange={updateAnswer} disabled={sending} hideOptionalTag />)}
          </div>
        </details>}
      </fieldset>}
      <section className="form-step">
      <StepTitle number={form.subject ? "04" : "03"}>Votre message</StepTitle>
      <label><span className="field-label">Votre demande en quelques mots <span className="required" aria-hidden="true">*</span></span>
        <textarea name="message" rows={5} placeholder={form.subject === "Support IT" ? "Présentez votre entreprise, votre organisation actuelle et ce que vous attendez d’un support informatique." : "Présentez votre activité et ajoutez le contexte utile à votre demande."} value={form.message} onChange={update} required minLength={10} maxLength={5000} aria-describedby="message-help" disabled={sending} />
      </label>
      <p id="message-help" className="contact-question-help">Ne communiquez pas de mot de passe, de code d’accès ni de données confidentielles.</p>
      </section>
      <div className="form-submit">
      <p className="form-privacy">En envoyant ce formulaire, vous acceptez que ProDigital enregistre ces informations pour traiter votre demande et vous répondre. <a href="#/confidentialite">En savoir plus</a>.</p>
      <button type="submit" className="button" disabled={sending}>{sending ? "Envoi en cours…" : "Envoyer ma demande"} <ArrowUpRight size={18} aria-hidden="true" /></button>
      </div>

      {status === "invalid" && <section className="prepared contact-alert" role="alert">
        <CircleAlert aria-hidden="true" />
        <div>
          <h3 ref={resultRef} tabIndex={-1}>Votre demande n’a pas été envoyée.</h3>
          <p>{feedback.message}</p>
          {!!feedback.errors.length && <ul>{feedback.errors.map(error => <li key={error.field}>{error.message}</li>)}</ul>}
        </div>
      </section>}

      {status === "unavailable" && <section className="prepared contact-alert" aria-labelledby="unavailable-heading" role="alert">
        <CircleAlert aria-hidden="true" />
        <div>
          <h3 id="unavailable-heading" ref={resultRef} tabIndex={-1}>Votre demande n’a pas pu être enregistrée.</h3>
          <p>Le service est momentanément indisponible et rien n’a été envoyé. Vos réponses sont conservées sur cette page : vous pouvez réessayer, ou nous écrire directement à {contactEmail}.</p>
          <button type="submit" className="button">Réessayer l’envoi <ArrowUpRight size={17} aria-hidden="true" /></button>
          <details className="contact-message-preview"><summary>Envoyer par e-mail à la place</summary>
            <pre>{message}</pre>
            <a className="button secondary" href={emailHref}>Ouvrir ma messagerie <Mail size={17} aria-hidden="true" /></a>
            <div className="contact-message-actions">
              <button type="button" className="download-link" onClick={copy}>Copier le message</button>
              <button type="button" className="download-link" onClick={download}><Download size={16} aria-hidden="true" /> Télécharger le message</button>
            </div>
            <p role="status">{copyStatus}</p>
          </details>
        </div>
      </section>}
    </form>
  );
}
