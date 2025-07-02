from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import torch
from transformers import  AutoProcessor, AutoModelForImageTextToText, BitsAndBytesConfig
import os
from pathlib import Path

app = FastAPI()

# The cache directory inside the container
CACHE_DIR = Path("/cache")
model_name = "google/gemma-3-4b-it"
model = None
tokenizer = None

@app.on_event("startup")
async def load_model():
    """
    Loads the model and tokenizer. On first run, it downloads the model
    to a persistent cache volume. On subsequent runs, it loads from the cache.
    """
    global model, tokenizer
    try:
        if not torch.cuda.is_available():
            raise RuntimeError("CUDA is not available. This service requires a GPU.")
        
        # Check if model already exists in the cache
        # If it does, from_pretrained will use the cached version automatically
        print(f"Loading model '{model_name}'. Caching to '{CACHE_DIR}'...")

        auth_token = os.getenv("HF_TOKEN")
        if not auth_token:
            print("Warning: HF_TOKEN environment variable not set. Download may fail for gated models.")

        # Define the 4-bit quantization configuration
        quantization_config = BitsAndBytesConfig(
            load_in_4bit=True,
            bnb_4bit_quant_type="nf4",
            bnb_4bit_compute_dtype=torch.bfloat16
        )
        
        tokenizer = AutoProcessor.from_pretrained(
            model_name,
            cache_dir=CACHE_DIR,
            token=auth_token
        )
        
        model = AutoModelForImageTextToText.from_pretrained(
            model_name,
            quantization_config=quantization_config,
            cache_dir=CACHE_DIR,
            token=auth_token
        )

        print(f"'{model_name}' loaded successfully onto CUDA device.")

    except Exception as e:
        print(f"FATAL: Could not load model. Error: {e}")
        # In a real scenario, you might want to handle this more gracefully

# --- The rest of the file (Prompt class, /health, /generate endpoints) remains the same ---

class Prompt(BaseModel):
    text: str

@app.get("/health")
async def health_check():
    if model is None or tokenizer is None:
        return {"status": "error", "detail": "Model not loaded. Check server logs."}
    return {"status": "ok", "model_name": model_name}

@app.post("/generate")
async def generate(prompt: Prompt):
    if model is None:
        raise HTTPException(status_code=503, detail="Model is not available. Please check server logs.")
    
    inputs = tokenizer(prompt.text, return_tensors="pt").to("cuda")
    outputs = model.generate(**inputs, max_new_tokens=250)
    generated_text = tokenizer.decode(outputs[0], skip_special_tokens=True)
    return {"generated_text": generated_text}