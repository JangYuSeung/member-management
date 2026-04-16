from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class MemberCreate(BaseModel):
    username: str
    email: str
    password: str
    name: str
    phone: Optional[str] = None

class MemberUpdate(BaseModel):
    email: Optional[str] = None
    name: Optional[str] = None
    phone: Optional[str] = None

class PasswordChange(BaseModel):
    current_password: str
    new_password: str

class MemberResponse(BaseModel):
    id: int
    username: str
    email: str
    name: str
    phone: Optional[str]
    created_at: datetime
    class Config:
        from_attributes = True