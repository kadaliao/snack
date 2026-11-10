#!/usr/bin/env node
// Checks deck/1 files (spec/deck-format.md) before they go into the Inbox.
//
//   node tools/deck-lint.mjs a.deck.json b.deck.json
//
// Prints each problem as `file: where: what`. Errors make Snack skip a card or the
// whole file; warnings are things that still load but play worse. Exits 1 on any
// error. No dependencies.

import { readFileSync, realpathSync } from 'node:fs'
import { basename } from 'node:path'
import { fileURLToPath } from 'node:url'

const KINDS = ['phrase', 'pattern', 'fix', 'qa']
const LANG = /^[A-Za-z]{2,3}(-[A-Za-z0-9]+)*$/
const DECK_KEYS = ['id', 'title', 'source', 'lang', 'description', 'updatedAt']
const CARD_KEYS = [
  'id', 'kind', 'front', 'back', 'reading', 'context', 'example', 'why', 'pattern',
  'distractors', 'tiles', 'tags', 'seen', 'addedAt', 'deleted',
]
const TEXT_LIMITS = { id: 200, front: 2000, back: 2000, reading: 500, context: 2000, example: 2000, why: 500, pattern: 500 }

const isText = v => typeof v === 'string' && v.trim() !== ''
const isDate = v => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}T/.test(v) && !Number.isNaN(Date.parse(v))
const isTextList = v => Array.isArray(v) && v.every(isText)
const bare = s => s.replace(/\s+/g, '')
const fold = s => s.toLowerCase().replace(/\s+/g, ' ').trim()

export function lint(text, name = 'deck') {
  const errors = []
  const warnings = []
  const error = (at, what) => errors.push(`${at}: ${what}`)
  const warn = (at, what) => warnings.push(`${at}: ${what}`)

  if (!name.endsWith('.deck.json')) warn('file', 'name does not end in .deck.json, so Snack will not read it')

  let file
  try {
    file = JSON.parse(text)
  } catch (e) {
    error('file', `not JSON (${e.message})`)
    return { errors, warnings }
  }
  if (file === null || typeof file !== 'object' || Array.isArray(file)) {
    error('file', 'not a JSON object')
    return { errors, warnings }
  }
  if (file.format !== 'deck/1') error('format', `must be "deck/1", is ${JSON.stringify(file.format)}`)

  const deck = file.deck
  if (deck === null || typeof deck !== 'object' || Array.isArray(deck)) {
    error('deck', 'missing, or not an object')
  } else {
    if (!isText(deck.id)) error('deck.id', 'missing, or empty')
    if (!isText(deck.title)) error('deck.title', 'missing, or empty')
    if (deck.source !== undefined && typeof deck.source !== 'string') error('deck.source', 'not a string')
    if (deck.description !== undefined && typeof deck.description !== 'string') error('deck.description', 'not a string')
    if (deck.updatedAt !== undefined && !isDate(deck.updatedAt)) error('deck.updatedAt', 'not an ISO 8601 time')
    if (deck.lang !== undefined) {
      if (deck.lang === null || typeof deck.lang !== 'object') error('deck.lang', 'not an object')
      else
        for (const k of ['target', 'native'])
          if (deck.lang[k] !== undefined && !(typeof deck.lang[k] === 'string' && LANG.test(deck.lang[k])))
            error(`deck.lang.${k}`, `not a language code like "en" or "ja": ${JSON.stringify(deck.lang[k])}`)
    }
    for (const k of Object.keys(deck)) if (!DECK_KEYS.includes(k)) warn(`deck.${k}`, 'unknown field, ignored')
  }

  if (!Array.isArray(file.cards)) {
    error('cards', 'missing, or not an array')
    return { errors, warnings }
  }
  if (file.cards.length === 0) warn('cards', 'no cards')

  const ids = new Map()
  file.cards.forEach((card, i) => {
    const at = `cards[${i}]${card && isText(card.id) ? ` (${card.id})` : ''}`
    if (card === null || typeof card !== 'object' || Array.isArray(card)) {
      error(at, 'not an object')
      return
    }
    for (const k of ['id', 'front', 'back']) if (!isText(card[k])) error(`${at}.${k}`, 'missing, or empty')
    if (!KINDS.includes(card.kind)) error(`${at}.kind`, `must be one of ${KINDS.join(', ')}, is ${JSON.stringify(card.kind)}`)
    for (const [k, n] of Object.entries(TEXT_LIMITS)) {
      if (card[k] === undefined) continue
      if (typeof card[k] !== 'string') error(`${at}.${k}`, 'not a string')
      else if (card[k].length > n) error(`${at}.${k}`, `longer than ${n} characters`)
    }
    for (const k of ['distractors', 'tiles', 'tags'])
      if (card[k] !== undefined && !isTextList(card[k])) error(`${at}.${k}`, 'not a list of non-empty strings')
    if (card.seen !== undefined && !(Number.isInteger(card.seen) && card.seen >= 0)) error(`${at}.seen`, 'not a whole number ≥ 0')
    if (card.addedAt !== undefined && !isDate(card.addedAt)) error(`${at}.addedAt`, 'not an ISO 8601 time')
    if (card.deleted !== undefined && typeof card.deleted !== 'boolean') error(`${at}.deleted`, 'not true or false')
    for (const k of Object.keys(card)) if (!CARD_KEYS.includes(k)) warn(`${at}.${k}`, 'unknown field, ignored')

    if (isText(card.id)) {
      if (ids.has(card.id)) error(`${at}.id`, `same id as cards[${ids.get(card.id)}]`)
      else ids.set(card.id, i)
    }
    if (!isText(card.back)) return

    if (isTextList(card.tiles) && bare(card.tiles.join('')) !== bare(card.back))
      error(`${at}.tiles`, 'joined together they are not the back')
    if (isTextList(card.distractors)) {
      if (card.distractors.some(d => fold(d) === fold(card.back))) error(`${at}.distractors`, 'one of them is the answer')
      if (card.distractors.length < 2) warn(`${at}.distractors`, 'fewer than 2; the rest come from the deck')
    }
    if (card.kind === 'pattern') {
      if (!isText(card.pattern)) warn(`${at}.pattern`, 'a pattern card without its frame')
      else if (!card.pattern.includes('___')) warn(`${at}.pattern`, 'no ___ for the parts that change')
    }
    if (typeof card.example === 'string' && !fold(card.example).includes(fold(card.back)) && card.kind !== 'pattern')
      warn(`${at}.example`, 'does not hold the back, so it cannot be blanked')
  })
  return { errors, warnings }
}

function main(paths) {
  if (paths.length === 0) {
    console.error('usage: node tools/deck-lint.mjs <file.deck.json>...')
    return 2
  }
  let failed = false
  for (const path of paths) {
    let text
    try {
      text = readFileSync(path, 'utf8')
    } catch (e) {
      console.log(`${path}: cannot read (${e.code ?? e.message})`)
      failed = true
      continue
    }
    const { errors, warnings } = lint(text, basename(path))
    for (const e of errors) console.log(`${path}: error: ${e}`)
    for (const w of warnings) console.log(`${path}: warning: ${w}`)
    if (errors.length === 0) {
      const cards = JSON.parse(text).cards.length
      console.log(`${path}: ok, ${cards} cards${warnings.length ? `, ${warnings.length} warnings` : ''}`)
    }
    failed ||= errors.length > 0
  }
  return failed ? 1 : 0
}

// Run as a command, also through a symlink (the make-deck skill has one).
const isMain = process.argv[1] !== undefined && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)
if (isMain) process.exitCode = main(process.argv.slice(2))
