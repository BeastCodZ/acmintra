from fastapi import FastAPI, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware

from PIL import Image
import easyocr

reader = easyocr.Reader(["en"], gpu=False)
import io

from receipt_ai import parse_receipt_with_llm

app = FastAPI(title="Receipt Intelligence API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def run_ocr(image_bytes: bytes) -> str:
    image = Image.open(io.BytesIO(image_bytes))

    # detail=0 returns only text strings
    lines = reader.readtext(image, detail=0)

    return "\n".join(lines)

@app.get("/")
def root():
    return {
        "status": "running",
        "service": "Receipt Intelligence API",
    }


@app.post("/analyze")
async def analyze(file: UploadFile = File(...)):
    """
    Upload a receipt image and return structured data extracted by OCR + LLM.
    """

    image_bytes = await file.read()

    # OCR
    ocr_text = run_ocr(image_bytes)

    # LLM extraction
    result = parse_receipt_with_llm(ocr_text)

    # Include OCR output for debugging/transparency
    result["ocr_text"] = ocr_text

    return result