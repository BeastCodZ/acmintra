## Setup
1. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```
2. Ensure Ollama is running and your preferred model is pulled:
   ```bash
   ollama pull qwen3:4b
   ```
3. Run the server:
   ```bash
   uvicorn main:app --reload
   ```

## API Endpoints
- `POST /analyze`: Upload an HTML statement to receive full analysis.
