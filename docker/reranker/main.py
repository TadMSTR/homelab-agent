"""
Jina-compatible reranker API wrapper using FlashRank.

Exposes POST /v1/rerank with Jina's request/response format,
backed by FlashRank for CPU-only, zero-cost local reranking.
Designed as a drop-in replacement for Jina's API so LibreChat
can use it via jinaApiUrl without modification.
"""

import os
import time
import logging
from fastapi import FastAPI, Request
from pydantic import BaseModel, Field
from typing import Optional
from contextlib import asynccontextmanager

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("reranker")

# Global ranker instance — loaded once at startup
ranker = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    global ranker
    from flashrank import Ranker
    model_name = os.getenv("RERANKER_MODEL", "ms-marco-MiniLM-L-12-v2")
    logger.info(f"Loading FlashRank model: {model_name}")
    ranker = Ranker(model_name=model_name)
    logger.info("FlashRank model loaded successfully")
    yield

app = FastAPI(title="Local Reranker (Jina-compatible)", lifespan=lifespan)


class RerankRequest(BaseModel):
    model: Optional[str] = "flashrank"
    query: str
    documents: list
    top_n: Optional[int] = None
    return_documents: Optional[bool] = False

class RerankResultItem(BaseModel):
    index: int
    relevance_score: float
    document: Optional[dict] = None

class RerankUsage(BaseModel):
    total_tokens: int = 0

class RerankResponse(BaseModel):
    model: str = "flashrank"
    results: list[RerankResultItem]
    usage: RerankUsage


@app.post("/v1/rerank", response_model=RerankResponse)
async def rerank(req: RerankRequest):
    from flashrank import RerankRequest as FRRequest

    start = time.time()

    # Normalize documents — Jina accepts strings or {"text": "..."} dicts
    passages = []
    for i, doc in enumerate(req.documents):
        if isinstance(doc, str):
            passages.append({"id": i, "text": doc})
        elif isinstance(doc, dict) and "text" in doc:
            passages.append({"id": i, "text": doc["text"]})
        else:
            passages.append({"id": i, "text": str(doc)})

    fr_request = FRRequest(query=req.query, passages=passages)
    raw_results = ranker.rerank(fr_request)

    sorted_results = sorted(raw_results, key=lambda r: r["score"], reverse=True)
    if req.top_n:
        sorted_results = sorted_results[:req.top_n]

    results = []
    for r in sorted_results:
        item = RerankResultItem(
            index=r["id"],
            relevance_score=r["score"],
        )
        if req.return_documents:
            item.document = {"text": r["text"]}
        results.append(item)

    elapsed = time.time() - start
    logger.info(f"Reranked {len(req.documents)} docs in {elapsed:.3f}s, returning top {len(results)}")

    total_chars = len(req.query) + sum(len(p["text"]) for p in passages)
    est_tokens = total_chars // 4

    return RerankResponse(
        model=req.model or "flashrank",
        results=results,
        usage=RerankUsage(total_tokens=est_tokens),
    )


@app.get("/health")
async def health():
    return {"status": "ok", "model_loaded": ranker is not None}
