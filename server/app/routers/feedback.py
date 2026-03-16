from fastapi import APIRouter, HTTPException
from typing import List
from app import crud, models

router = APIRouter(prefix="/api/feedback", tags=["Feedback"])

@router.post("", response_model=models.Feedback)
async def submit_feedback(feedback: models.Feedback):
    """Store new feedback from the mobile app."""
    return await crud.create_feedback(feedback)

@router.get("", response_model=List[models.Feedback])
async def list_feedback(skip: int = 0, limit: int = 100):
    """Retrieve all feedback (Admin function)."""
    return await crud.get_feedback(skip=skip, limit=limit)
