# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [2026-06-02]

### Added
- Added marketplace listing syndication foundations, including listing events, content snapshots, media assets, scrape-run tracking, scrape-error logging, platform pricing rules, price quotes, and publication queue tables.
- Added a conversation-layer foundation for marketplace inquiries, including normalized conversation threads/messages, active conversation queue views, urgency rules, human-reviewed lead-quality fields, and public-safe synthetic smoke-test data.
- Added public-safe AgentSkill playbooks for Craigslist chat capture, Craigslist email replies, active conversation queue review, conversation monitor triage, platform message ingestion, and listing price synchronization.

### Changed
- Expanded CI smoke coverage to load ordered feature migrations, seed synthetic marketplace/conversation examples, and verify the active conversation queue regression path.
