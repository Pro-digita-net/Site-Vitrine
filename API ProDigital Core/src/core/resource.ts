import { z } from "zod";
import type { Ctx } from "./context.js";
import type { Permission } from "../shared/tokens.js";

export type Row = Record<string, unknown>;

/**
 * Définition d'une ressource exposée. Tout identifiant SQL (table, colonnes, tris, filtres) vient
 * d'ici — jamais d'une requête client — et ne décrit que ce que le SQL de référence autorise.
 */
export interface ResourceDef {
  name: string;
  table: string;
  tag: string;
  title: string;
  read: Permission | null;
  write?: Permission;
  columns: readonly string[];
  create?: z.ZodObject;
  update?: z.ZodObject;
  filters?: Record<string, { column: string; schema: z.ZodType }>;
  search?: readonly string[];
  sorts: readonly string[];
  defaultSort: string;
  /** Tri secondaire stable (défaut : id). */
  tiebreak?: string;
  /** Colonne organization_id présente (défaut : oui). */
  orgScoped?: boolean;
  /** Lecture unitaire par id (défaut : oui). */
  byId?: boolean;
  /** Archivage logique : le SQL n'accorde ni DELETE ni TRUNCATE. */
  archive?: { set: string; unset: string; active?: string };
  hooks?: {
    beforeCreate?: (ctx: Ctx, input: Row) => Promise<Row> | Row;
    afterCreate?: (ctx: Ctx, row: Row) => Promise<void>;
  };
}

const IDENT = /^[a-z_][a-z0-9_]*(\.[a-z_][a-z0-9_]*)?$/;
export function defineResource(def: ResourceDef): ResourceDef {
  const idents = [def.table, ...def.columns, ...def.sorts, ...(def.search ?? []), ...Object.values(def.filters ?? {}).map((f) => f.column),
    ...Object.keys(def.create?.shape ?? {}), ...Object.keys(def.update?.shape ?? {})];
  for (const ident of idents) if (!IDENT.test(ident)) throw new Error(`Identifiant SQL invalide dans ${def.name} : ${ident}`);
  if (!def.sorts.includes(def.defaultSort.replace(/^-/, ""))) throw new Error(`Tri par défaut invalide : ${def.name}`);
  return def;
}

// Briques de validation partagées.
export const uuid = z.uuid();
export const text = (max: number, min = 1) => z.string().trim().min(min).max(max);
export const optional = <T extends z.ZodType>(schema: T) => schema.nullable().optional();
export const email = z.email().max(254).transform((v) => v.toLowerCase());
export const phone = z.string().trim().regex(/^[0-9+().\s-]{3,30}$/, "Téléphone invalide");
export const country = z.string().regex(/^[A-Z]{2}$/, "Code pays ISO 3166-1 alpha-2");
