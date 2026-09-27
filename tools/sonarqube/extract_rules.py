#!/usr/bin/env python3
"""Extrait les règles actives d'un Quality Profile SonarQube et calcule le diff
avec le manifest local (nouvelles / modifiées / dépréciées).

Ce script ne fait que lire SonarQube et comparer : il n'écrit jamais dans le
manifest ni dans les skills — ça, c'est le rôle de la commande slash
`/sonar-to-skills` qui consomme le fichier de diff produit ici.

Usage :
    python extract_rules.py --language py --profile strong

Variables d'environnement (voir .env.example) :
    SONAR_HOST_URL   URL du serveur SonarQube (défaut : http://localhost:9000)
    SONAR_TOKEN      Token utilisateur SonarQube, obligatoire (Basic Auth,
                      token en username, mot de passe vide)
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

import httpx
from dotenv import load_dotenv

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_HOST_URL = "http://localhost:9000"
DEFAULT_MANIFEST_PATH = REPO_ROOT / ".claude/sonar-rules/manifest.json"
DEFAULT_OUT_DIR = REPO_ROOT / "docs/sonarqube"
PAGE_SIZE = 500
KEPT_DESCRIPTION_SECTIONS = {"introduction", "how_to_fix"}


class SonarConfigError(RuntimeError):
    """Configuration invalide ou manquante (host, token, profil introuvable)."""


def load_config() -> tuple[str, str]:
    """Charge l'URL du serveur et le token depuis l'environnement (.env)."""
    load_dotenv()
    host_url = os.environ.get("SONAR_HOST_URL", DEFAULT_HOST_URL).rstrip("/")
    token = os.environ.get("SONAR_TOKEN")
    if not token:
        raise SonarConfigError(
            "SONAR_TOKEN manquant. Définis-le dans .env (voir .env.example)."
        )
    return host_url, token


def resolve_profile_key(client: httpx.Client, language: str, profile_name: str) -> str:
    """Trouve la clé du Quality Profile nommé `profile_name` pour `language`."""
    response = client.get("/api/qualityprofiles/search", params={"language": language})
    response.raise_for_status()
    profiles = response.json().get("profiles", [])
    for profile in profiles:
        if profile["name"] == profile_name:
            return profile["key"]
    known = ", ".join(p["name"] for p in profiles) or "aucun"
    raise SonarConfigError(
        f"Profil '{profile_name}' introuvable pour la langue '{language}'. "
        f"Profils disponibles : {known}."
    )


def fetch_active_rules(client: httpx.Client, profile_key: str) -> list[dict]:
    """Pagine sur /api/rules/search et retourne les règles actives non-template.

    Le champ `total` de cette API est peu fiable (bug connu sur les facettes
    imbriquées `impacts`) : on s'arrête dès qu'une page renvoie moins de
    résultats que PAGE_SIZE, jamais sur la base de `total`.
    """
    rules: list[dict] = []
    page = 1
    while True:
        response = client.get(
            "/api/rules/search",
            params={
                "qprofile": profile_key,
                "activation": "true",
                "status": "READY",
                "ps": PAGE_SIZE,
                "p": page,
            },
        )
        response.raise_for_status()
        batch = response.json().get("rules", [])
        rules.extend(r for r in batch if not r.get("isTemplate"))
        if len(batch) < PAGE_SIZE:
            break
        page += 1
    return rules


def trim_rule(rule: dict) -> dict:
    """Ne garde que les champs utiles au skill (réduit le coût du prompt Haiku)."""
    sections = [
        s
        for s in rule.get("descriptionSections", [])
        if s.get("key") in KEPT_DESCRIPTION_SECTIONS
    ]
    return {
        "key": rule["key"],
        "name": rule.get("name"),
        "severity": rule.get("severity"),
        "type": rule.get("type"),
        "sysTags": rule.get("sysTags", []),
        "context": rule.get("context"),
        "updatedAt": rule.get("updatedAt"),
        "descriptionSections": sections,
    }


def load_manifest_language(path: Path, language: str) -> dict:
    """Charge la portion du manifest correspondant à `language` (vide si absent)."""
    if not path.exists():
        return {}
    manifest = json.loads(path.read_text(encoding="utf-8"))
    return manifest.get(language, {})


def diff_rules(rules: list[dict], manifest_language: dict) -> dict:
    """Compare les règles actives récupérées au manifest existant.

    - nouvelle : clé absente du manifest
    - modifiée : `updatedAt` ou `severity` différent de l'état mémorisé
    - dépréciée : clé présente dans le manifest mais absente des règles actives
    """
    known_keys = {k for k in manifest_language if k != "_meta"}
    active_keys = {r["key"] for r in rules}

    new_rules = []
    modified_rules = []
    for rule in rules:
        entry = manifest_language.get(rule["key"])
        if entry is None:
            new_rules.append(trim_rule(rule))
        elif entry.get("updatedAt") != rule.get("updatedAt") or entry.get("severity") != rule.get(
            "severity"
        ):
            modified_rules.append(trim_rule(rule))

    deprecated_keys = sorted(known_keys - active_keys)

    return {"new": new_rules, "modified": modified_rules, "deprecated": deprecated_keys}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Extrait les règles actives d'un Quality Profile SonarQube et "
        "calcule le diff avec le manifest local.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--language", required=True, help="Code langage SonarQube (ex: py, ts)")
    parser.add_argument(
        "--profile",
        required=True,
        help="Nom du Quality Profile ciblé, tel que défini sur le serveur SonarQube",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=DEFAULT_MANIFEST_PATH,
        help=f"Chemin du manifest (défaut : {DEFAULT_MANIFEST_PATH})",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=None,
        help="Chemin du fichier de diff en sortie "
        "(défaut : docs/sonarqube/diff_<language>_<profile>.json)",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    out_path = args.out or DEFAULT_OUT_DIR / f"diff_{args.language}_{args.profile}.json"

    try:
        host_url, token = load_config()
    except SonarConfigError as exc:
        print(f"Erreur de configuration : {exc}", file=sys.stderr)
        sys.exit(1)

    try:
        with httpx.Client(base_url=host_url, auth=(token, ""), timeout=30.0) as client:
            profile_key = resolve_profile_key(client, args.language, args.profile)
            rules = fetch_active_rules(client, profile_key)
    except SonarConfigError as exc:
        print(f"Erreur : {exc}", file=sys.stderr)
        sys.exit(1)
    except httpx.HTTPStatusError as exc:
        print(
            f"Erreur SonarQube ({exc.response.status_code}) : {exc.response.text}",
            file=sys.stderr,
        )
        sys.exit(1)
    except httpx.HTTPError as exc:
        print(f"Erreur réseau vers SonarQube : {exc}", file=sys.stderr)
        sys.exit(1)

    manifest_language = load_manifest_language(args.manifest, args.language)
    diff = diff_rules(rules, manifest_language)

    output = {
        "language": args.language,
        "profile": args.profile,
        "profileKey": profile_key,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        **diff,
    }

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(output, indent=2, ensure_ascii=False), encoding="utf-8")

    print(
        f"{len(diff['new'])} nouvelle(s), {len(diff['modified'])} modifiée(s), "
        f"{len(diff['deprecated'])} dépréciée(s) → {out_path}"
    )


if __name__ == "__main__":
    main()
