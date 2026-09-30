-- The LLM module was pure/claude.lua while Claude was its only model; with
-- Ollama and agy beside it, it is pure/llm.lua (asked for in the vault's
-- Improvment.md). This name stays so that require('pure.claude') in
-- personal scripts (the vault's Claude/*.lua) keeps working.
return require('pure.llm')
