import os
from google import genai
from google.genai import types
from dotenv import load_dotenv

# Load env from the backend directory
load_dotenv("/Users/sebastianescobar/Documents/Ticio/EduVerse/EduVerseApp/backend/.env")

api_key = os.getenv("GOOGLE_API_KEY")
model_name = os.getenv("AI_MODEL_NAME")

print(f"--- EduVerse Gemma 4 Validator ---")
print(f"Target Model: {model_name}")

client = genai.Client(api_key=api_key)

try:
    print("\n1. Listing available models...")
    # Some older versions or specific tiers might not support list() 
    # Let's try to get a specific model immediately or list all.
    try:
        models = client.models.list()
        for m in models:
            print(f"- {m.name}")
    except Exception as e:
        print(f"⚠️ Could not list models: {e}")

    test_ids = [model_name, f"models/{model_name}", "gemma-2-27b-it"]
    
    for tid in test_ids:
        print(f"\n2. Testing generation with: {tid}")
        try:
            response = client.models.generate_content(
                model=tid,
                contents="Hola, responde 'ok' si me escuchas."
            )
            print(f"✅ Success with {tid}: {response.text}")
            break
        except Exception as e:
            print(f"❌ Failed {tid}: {e}")

    print("\n--- Validation Complete ---")

except Exception as e:
    print(f"❌ Error during validation: {str(e)}")
