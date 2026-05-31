from typing import Optional
from pydantic import BaseModel, Field, EmailStr


class UserRegister(BaseModel):
    email: EmailStr
    otp_code: str = Field(min_length=6, max_length=6)
    username: str = Field(min_length=3, max_length=32)
    display_name: str = Field(min_length=1, max_length=64)
    password: str = Field(min_length=6, max_length=128)


class SendOtpIn(BaseModel):
    email: EmailStr


class UserLogin(BaseModel):
    username: str
    password: str


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int


class UpdateProfileIn(BaseModel):
    display_name: Optional[str] = Field(default=None, min_length=1, max_length=64)
    cycle_start_day: Optional[int] = Field(default=None, ge=1, le=28)
    email: Optional[EmailStr] = Field(default=None)


class ChangePasswordIn(BaseModel):
    current_password: str
    new_password: str = Field(min_length=6, max_length=128)


class MessageOut(BaseModel):
    message: str
