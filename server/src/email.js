// Notification e-mail « Une nouvelle demande vous attend », selon le modèle
// ProDigital (en-tête logo, tableau des informations, message, bouton de
// réponse, référence). HTML en tableaux + styles en ligne pour les messageries.

import nodemailer from "nodemailer";
import { readFileSync } from "node:fs";
import { config } from "./config.js";
import { fullName, summaryText } from "./summary.js";

const LOGO = readFileSync(new URL("../assets/logo-email.png", import.meta.url));
const LOGO_CID = "logo@pro-digital.net";

const C = {
  page: "#f3f4f7",
  card: "#ffffff",
  border: "#e6e8ee",
  ink: "#10202b",
  muted: "#5d6a75",
  blue: "#2857ff",
  soft: "#f5f6fa",
};
const FONT = "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif";

const escape = (value) =>
  String(value ?? "").replace(/[&<>"']/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[ch]);
const paragraphs = (value) => escape(value).replace(/\n/g, "<br>");
// Les en-têtes ne doivent jamais contenir de retour à la ligne (injection).
const headerSafe = (value) => String(value).replace(/[\r\n]+/g, " ").slice(0, 180);

export function notificationRows(row) {
  const rows = [
    ["Contact", fullName(row)],
    ["E-mail", row.email],
    ["Entreprise", row.company || "Non précisée"],
    [row.subject_group, row.subject],
  ];
  for (const detail of row.details ?? []) rows.push([detail.label, detail.value]);
  return rows;
}

export function replyHref(row) {
  const subject = `Votre demande ProDigital — ${row.subject}`;
  const body = `Bonjour ${row.given_name},\n\nMerci pour votre demande. \n\n`;
  return `mailto:${encodeURIComponent(row.email)}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
}

export function notificationSubject(row) {
  return headerSafe(`Nouvelle demande — ${row.subject} — ${fullName(row)}`);
}

export function notificationHtml(row) {
  const site = config.publicSiteUrl;
  const siteLabel = site.replace(/^https?:\/\//, "");
  const tableRows = notificationRows(row)
    .map(([label, value], i, all) => {
      const border = i < all.length - 1 ? `border-bottom:1px solid ${C.border};` : `border-bottom:1px solid ${C.border};`;
      return `<tr>
              <td valign="top" style="${border}padding:11px 12px 11px 0;width:34%;font:400 13px/1.5 ${FONT};color:${C.muted};">${escape(label)}</td>
              <td valign="top" style="${border}padding:11px 0;font:400 13px/1.5 ${FONT};color:${C.ink};word-break:break-word;">${escape(value)}</td>
            </tr>`;
    })
    .join("\n");

  return `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light only">
<title>Une nouvelle demande vous attend</title>
</head>
<body style="margin:0;padding:0;background:${C.page};">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">${escape(`${fullName(row)} — ${row.subject}`)}</div>
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background:${C.page};">
  <tr>
    <td align="center" style="padding:24px 12px;">
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:560px;background:${C.card};border:1px solid ${C.border};border-radius:14px;">
        <tr>
          <td style="padding:20px 28px;border-bottom:1px solid ${C.border};">
            <table role="presentation" cellspacing="0" cellpadding="0" border="0"><tr>
              <td style="padding-right:12px;"><img src="cid:${LOGO_CID}" width="28" height="28" alt="" style="display:block;border:0;"></td>
              <td style="font:700 18px/1 ${FONT};color:${C.ink};letter-spacing:-0.2px;">ProDigital</td>
            </tr></table>
          </td>
        </tr>
        <tr>
          <td style="padding:26px 28px 6px;">
            <p style="margin:0 0 12px;font:700 10px/1.4 ${FONT};letter-spacing:2px;text-transform:uppercase;color:${C.blue};">Assistant ProDigital</p>
            <h1 style="margin:0 0 14px;font:700 24px/1.25 ${FONT};color:${C.ink};letter-spacing:-0.4px;">Une nouvelle demande vous attend.</h1>
            <p style="margin:0 0 18px;font:400 14px/1.6 ${FONT};color:${C.ink};">Bonjour, je suis l’assistant automatique ProDigital. Une nouvelle demande vient d’être enregistrée sur le site. Voici les informations pour préparer votre réponse.</p>
            <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="border-collapse:collapse;">
            ${tableRows}
            </table>
            <h2 style="margin:26px 0 12px;font:700 15px/1.4 ${FONT};color:${C.ink};">Son message</h2>
            <div style="background:${C.soft};border-radius:10px;padding:14px 16px;font:400 13px/1.65 ${FONT};color:${C.ink};word-break:break-word;">${paragraphs(row.message)}</div>
            <table role="presentation" cellspacing="0" cellpadding="0" border="0" style="margin:24px 0 18px;"><tr>
              <td style="border-radius:8px;background:${C.blue};">
                <a href="${escape(replyHref(row))}" style="display:inline-block;padding:11px 16px;font:500 14px/1.2 ${FONT};color:#ffffff;text-decoration:none;border-radius:8px;">Répondre à la demande</a>
              </td>
            </tr></table>
            <p style="margin:0;font:400 10px/1.5 ${FONT};color:${C.muted};">Référence de votre échange</p>
            <p style="margin:2px 0 18px;font:400 10px/1.5 ${FONT};color:${C.muted};word-break:break-all;">${escape(row.id)}</p>
            <p style="margin:0 0 24px;font:400 13px/1.6 ${FONT};color:${C.ink};">À bientôt,<br>Votre assistant ProDigital</p>
          </td>
        </tr>
        <tr>
          <td style="padding:16px 28px;border-top:1px solid ${C.border};background:#fafbfc;border-radius:0 0 14px 14px;">
            <p style="margin:0 0 4px;font:400 10px/1.6 ${FONT};color:${C.muted};">Notification envoyée automatiquement par l’assistant ProDigital. Répondez à ce message pour contacter le demandeur.</p>
            <a href="${escape(site)}" style="font:400 10px/1.6 ${FONT};color:${C.blue};text-decoration:underline;">${escape(siteLabel)}</a>
          </td>
        </tr>
      </table>
    </td>
  </tr>
</table>
</body>
</html>`;
}

export function notificationText(row) {
  return [
    "ASSISTANT PRODIGITAL",
    "Une nouvelle demande vous attend.",
    "",
    summaryText(row),
    "",
    `Répondre : écrivez à ${row.email} (ou répondez simplement à ce message).`,
    "",
    "Notification envoyée automatiquement par l’assistant ProDigital.",
    config.publicSiteUrl,
  ].join("\n");
}

let transport;
function getTransport() {
  const smtp = config.smtp;
  transport ??= nodemailer.createTransport({
    host: smtp.host,
    port: smtp.port,
    secure: smtp.security === "ssl",
    requireTLS: smtp.security === "starttls",
    ignoreTLS: smtp.security === "off",
    auth: smtp.user ? { user: smtp.user, pass: smtp.password } : undefined,
    connectionTimeout: 15000,
    greetingTimeout: 15000,
    socketTimeout: 30000,
    disableFileAccess: true,
    disableUrlAccess: true,
  });
  return transport;
}

/** Envoie la notification ; renvoie le Message-ID SMTP. Lève une erreur si le serveur refuse. */
export async function sendNotification(row) {
  if (!config.smtp.host || !config.smtp.from) {
    throw new Error("Messagerie non configurée (SMTP_HOST / SMTP_FROM)");
  }
  const info = await getTransport().sendMail({
    from: { name: "Assistant ProDigital", address: config.smtp.from },
    to: config.smtp.to,
    replyTo: { name: fullName(row), address: row.email },
    subject: notificationSubject(row),
    text: notificationText(row),
    html: notificationHtml(row),
    // Même référence à chaque tentative : les messageries regroupent les doublons éventuels.
    messageId: `<demande-${row.id}@pro-digital.net>`,
    headers: { "X-ProDigital-Request": row.id },
    attachments: [{ filename: "prodigital.png", content: LOGO, cid: LOGO_CID, contentType: "image/png" }],
  });
  if (Array.isArray(info.rejected) && info.rejected.length) {
    throw new Error(`Destinataire refusé par le serveur SMTP : ${info.rejected.join(", ")}`);
  }
  return info.messageId;
}
