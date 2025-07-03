from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import torch
from transformers import  (AutoProcessor,
                           AutoModelForImageTextToText,
                           BitsAndBytesConfig,
                           Gemma3ForConditionalGeneration, 
                           TorchAoConfig)
import os
from pathlib import Path

app = FastAPI()

# The cache directory inside the container
CACHE_DIR = Path("/cache")
model_name = "google/gemma-3-4b-it"
model = None
processor = None

@app.on_event("startup")
async def load_model():
    """
    Loads the model and processor. On first run, it downloads the model
    to a persistent cache volume. On subsequent runs, it loads from the cache.
    """
    global model, processor
    test_prompt = False
    if test_prompt:
        auth_token = os.getenv("HF_TOKEN")
        quantization_config = BitsAndBytesConfig(
                load_in_4bit=True,
                bnb_4bit_quant_type="nf4",
                bnb_4bit_compute_dtype=torch.bfloat16
                )
        model = Gemma3ForConditionalGeneration.from_pretrained(
            "google/gemma-3-4b-it",
            torch_dtype=torch.bfloat16,
            device_map="auto",
            quantization_config=quantization_config, 
            cache_dir=CACHE_DIR,
            token=auth_token,
        )
        processor = AutoProcessor.from_pretrained(
            "google/gemma-3-4b-it",
            token=auth_token,
            padding_side="left"
        )
         
    else:
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
            quan_method = 'bits'
            if quan_method == 'bits':
                quantization_config = BitsAndBytesConfig(
                load_in_4bit=True,
                bnb_4bit_quant_type="nf4",
                bnb_4bit_compute_dtype=torch.bfloat16
                )
            else:
                quantization_config = TorchAoConfig("int4_weight_only", group_size=128)
            
            processor = AutoProcessor.from_pretrained(
                model_name,
                cache_dir=CACHE_DIR,
                token=auth_token, 
                padding_side = 'left'
            )
            
            model = Gemma3ForConditionalGeneration.from_pretrained(
                model_name,
                torch_dtype=torch.bfloat16,
                quantization_config=quantization_config,
                cache_dir=CACHE_DIR,
                token=auth_token, 
                device_map="auto", 
                #attn_implementation="sdpa"
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
    if model is None or processor is None:
        return {"status": "error", "detail": "Model not loaded. Check server logs."}
    return {"status": "ok", "model_name": model_name}

@app.post("/generate")
async def generate(prompt: Prompt):
    if model is None:
        raise HTTPException(status_code=503, detail="Model is not available. Please check server logs.")
    test_prompt = False
    if test_prompt:
        messages = [
            {
                "role": "system",
                "content": [
                    {"type": "text", "text": "You are a helpful assistant."}
                ]
            },
            {
                "role": "user", "content": [
                    {"type": "image", "url": "https://huggingface.co/datasets/huggingface/documentation-images/resolve/main/pipeline-cat-chonk.jpeg"},
                    {"type": "text", "text": "What is shown in this image?"},
                ]
            },
        ]
        inputs = processor.apply_chat_template(
            messages,
            tokenize=True,
            return_dict=True,
            return_tensors="pt",
            add_generation_prompt=True,
        ).to("cuda")

        output = model.generate(**inputs, max_new_tokens=512, cache_implementation="static")
        generated_text = processor.decode(output[0], skip_special_tokens=True)
    else:
        agent_name = "DiffEQGemma"
        system_prompt = [
            f"{agent_name} is a helpful assistant, bioengineer, and expert python coder.", 
            f"{agent_name} carefully examines code for correctness and numerical computation best practices.",
            f"{agent_name} takes pride in ensuring the user's request is fulfilled in a correct and straightforward manner.",
            f"{agent_name} is an expert in correctly solving, nondimensionalizing, and describing systems using differential equations.",
            f"{agent_name} relaxes and thinks deeply before correctly executing mathematical and coding tasks." 
        ]
        system_prompt = " ".join(system_prompt)
        #prompt = f"{agent_name} reply to the user's prompt: {prompt.text}"
        messages = [
            {
                "role": "system",
                "content":[
                    {"type": "text", "text": system_prompt}
                ],
            },
            {"role": "user",
            "content": [
                    {"type": "text", "text":prompt.text},
                ]
            
            },
        ]
    
        inputs = processor.apply_chat_template(
            messages,
            tokenize=True,
            return_dict=True,
            return_tensors="pt",
            add_generation_prompt=True,
        ).to("cuda")
        output = model.generate(**inputs, max_new_tokens=1200 , cache_implementation="static")
        generated_text = processor.decode(output[0], skip_special_tokens=True)
        #cleaned_text = generated_text.replace(formatted_prompt, "").strip()
    return {"generated_text": generated_text}