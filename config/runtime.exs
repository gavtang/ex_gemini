import Config

config :ex_gemini, ExGemini, api_key: System.get_env("GEMINI_API_KEY")
