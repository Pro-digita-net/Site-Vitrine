import type { Db } from "../shared/db.js";
import type { ResourceDef, Row } from "./resource.js";

// Version d'une ligne : updated_at à la microseconde, pour le verrouillage optimiste (If-Match).
const VERSION = "(extract(epoch from updated_at) * 1000000)::bigint::text AS version";
const versioned = (def: ResourceDef) => def.columns.includes("updated_at");
const projection = (def: ResourceDef) => def.columns.join(", ") + (versioned(def) ? `, ${VERSION}` : "");
const escapeLike = (value: string) => value.replace(/[\\%_]/g, "\\$&");

export interface ListQuery { limit: number; offset: number; sort: string; q?: string; archived?: "false" | "true" | "all"; filters: Record<string, unknown> }

/** Accès SQL d'une ressource : requêtes paramétrées, identifiants issus de la définition uniquement. */
export class ResourceRepository {
  constructor(private def: ResourceDef) {}

  private scope(organizationId: string): { where: string[]; params: unknown[] } {
    // Défense en profondeur : le filtre d'organisation double la politique RLS.
    return this.def.orgScoped === false ? { where: [], params: [] } : { where: ["organization_id = $1"], params: [organizationId] };
  }

  async list(db: Db, organizationId: string, query: ListQuery): Promise<{ rows: Row[]; hasMore: boolean }> {
    const { where, params } = this.scope(organizationId);
    const add = (value: unknown) => { params.push(value); return `$${params.length}`; };
    for (const [name, value] of Object.entries(query.filters)) {
      const filter = this.def.filters?.[name];
      if (filter && value !== undefined) where.push(`${filter.column} = ${add(value)}`);
    }
    if (query.q && this.def.search?.length) {
      const p = add(`%${escapeLike(query.q)}%`);
      where.push(`(${this.def.search.map((c) => `${c} ILIKE ${p}`).join(" OR ")})`);
    }
    const active = this.def.archive?.active;
    if (active && query.archived !== "all") where.push(query.archived === "true" ? `NOT (${active})` : active);
    const desc = query.sort.startsWith("-");
    const column = this.def.sorts.find((s) => s === query.sort.replace(/^-/, "")) ?? this.def.defaultSort.replace(/^-/, "");
    const sql = `SELECT ${projection(this.def)} FROM ${this.def.table}${where.length ? ` WHERE ${where.join(" AND ")}` : ""}
      ORDER BY ${column} ${desc ? "DESC" : "ASC"} NULLS LAST, ${this.def.tiebreak ?? "id"} LIMIT ${add(query.limit + 1)} OFFSET ${add(query.offset)}`;
    const { rows } = await db.query<Row>(sql, params);
    return { rows: rows.slice(0, query.limit), hasMore: rows.length > query.limit };
  }

  async get(db: Db, organizationId: string, id: string): Promise<Row | null> {
    const { where, params } = this.scope(organizationId);
    params.push(id);
    const { rows } = await db.query<Row>(`SELECT ${projection(this.def)} FROM ${this.def.table} WHERE ${[...where, `id = $${params.length}`].join(" AND ")}`, params);
    return rows[0] ?? null;
  }

  async insert(db: Db, values: Row): Promise<Row> {
    // organization_id n'est jamais fourni : le DEFAULT iam.current_organization_id() et la RLS le fixent.
    const columns = Object.keys(values).filter((c) => values[c] !== undefined);
    const params = columns.map((c) => values[c]);
    const sql = columns.length
      ? `INSERT INTO ${this.def.table} (${columns.join(", ")}) VALUES (${columns.map((_, i) => `$${i + 1}`).join(", ")}) RETURNING ${projection(this.def)}`
      : `INSERT INTO ${this.def.table} DEFAULT VALUES RETURNING ${projection(this.def)}`;
    return (await db.query<Row>(sql, params)).rows[0]!;
  }

  /** Mise à jour conditionnée à la version lue par le client. Renvoie null si la version ne correspond plus. */
  async update(db: Db, organizationId: string, id: string, version: string, values: Row): Promise<Row | null> {
    const columns = Object.keys(values);
    const params: unknown[] = columns.map((c) => values[c]);
    params.push(organizationId, id, version);
    const n = columns.length;
    const { rows } = await db.query<Row>(
      `UPDATE ${this.def.table} SET ${columns.map((c, i) => `${c} = $${i + 1}`).join(", ")}
        WHERE organization_id = $${n + 1} AND id = $${n + 2} AND (extract(epoch from updated_at) * 1000000)::bigint::text = $${n + 3}
        RETURNING ${projection(this.def)}`, params);
    return rows[0] ?? null;
  }

  async setArchived(db: Db, organizationId: string, id: string, archived: boolean): Promise<Row | null> {
    const archive = this.def.archive!;
    const { rows } = await db.query<Row>(
      `UPDATE ${this.def.table} SET ${archived ? archive.set : archive.unset} WHERE organization_id = $1 AND id = $2 RETURNING ${projection(this.def)}`,
      [organizationId, id]);
    return rows[0] ?? null;
  }
}
