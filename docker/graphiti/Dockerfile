FROM zepai/knowledge-graph-mcp:1.0.2-standalone

# Install Anthropic and Voyage AI client packages into the app's venv
# (not bundled in the standalone image, required for our LLM/embedding config)
RUN pip install --no-cache-dir --target=/app/mcp/.venv/lib/python3.11/site-packages anthropic voyageai
