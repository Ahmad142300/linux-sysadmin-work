from flask import Flask, request, jsonify
from openai import OpenAI
import os
from dotenv import load_dotenv
from urllib.parse import urlparse
from models import db, ChatSession, Message
from datetime import datetime
from flask_cors import CORS
import logging
from google import genai
load_dotenv()
api_key = os.getenv("OPENAI_API_KEY")
# Check if the API key is set
if not api_key:
    raise ValueError("OPENAI_API_KEY environment variable not set.")
client = OpenAI(api_key=api_key)

app = Flask(__name__)
CORS(app)

# Database configuration
# Use DATABASE_URL env var like: postgresql+psycopg2://user:pass@host:5432/dbname
database_url = os.getenv('DATABASE_URL')
if database_url:
    app.config['SQLALCHEMY_DATABASE_URI'] = database_url
else:
    # Fallback to local SQLite for dev if no DATABASE_URL provided
    app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///chat.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db.init_app(app)

with app.app_context():
    db.create_all()

# -------------------------
# gpt4.1 Endpoint
# -------------------------
@app.route('/gpt-4.1', methods=['POST'])
def gpt_4_1():
    data = request.get_json(force=True) or {}
    user_message = (data.get('message') or '').strip()
    session_id = data.get('session_id')
    if not user_message:
        return jsonify({'error': 'Message is required'}), 400

    # Ensure a session exists (create if not provided)
    session = None
    if session_id is not None:
        session = ChatSession.query.get(session_id)
        if session is None:
            return jsonify({'error': 'Invalid session_id'}), 404
    else:
        if user_message is not None:
            session = ChatSession(title=user_message[:50])  # Use first 50 chars as title
        else:
            session = ChatSession(title="New Session")
        db.session.add(session)
        db.session.flush()  # get id

    # Persist user message
    db.session.add(Message(session_id=session.id, role='user', content=user_message))
    # Update session's last activity timestamp
    session.last_visited_at = datetime.utcnow()

    # Call OpenAI (or return a stub)
    try:
        response = client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {"role": "system", "content": "You are a helpful assistant."},
                {"role": "user", "content": user_message},
            ],
            timeout=15.0  # Optional: prevent the 37s hang if OpenAI is slow
        )
        reply = response.choices[0].message.content
    except Exception as e:
        # Log the actual error to the console/k8s logs for debugging
        print(f"ERROR: OpenAI call failed: {type(e).__name__} - {str(e)}")
        
        # Determine the user-facing message based on the error type
        if "rate_limit" in str(e).lower():
            reply = "System is busy (Rate Limit). Please try again in a moment."
        elif "insufficient_quota" in str(e).lower():
            reply = "API Quota exceeded. Please check billing."
        else:
            reply = f"Automated response (Technical error: {type(e).__name__})"

    # Persist assistant message
    db.session.add(Message(session_id=session.id, role='assistant', content=reply))
    db.session.commit()

    return jsonify({'response': reply, 'session_id': session.id})

genai_client = genai.Client(api_key=os.environ.get("GEMINI_API_KEY"))

@app.route('/gemini-3-flash', methods=['POST'])
def gemini_3_flash():
    data = request.get_json(force=True) or {}
    user_message = (data.get('message') or '').strip()
    session_id = data.get('session_id')
    
    if not user_message:
        return jsonify({'error': 'Message is required'}), 400

    # Session Management
    session = None
    if session_id is not None:
        session = ChatSession.query.get(session_id)
        if session is None:
            return jsonify({'error': 'Invalid session_id'}), 404
    else:
        session = ChatSession(title=user_message[:50])
        db.session.add(session)
        db.session.flush()

    # Persist User Message
    db.session.add(Message(session_id=session.id, role='user', content=user_message))
    session.last_visited_at = datetime.utcnow()

    try:
        # Call Gemini 3 Flash
        response = genai_client.models.generate_content(
            model="gemini-3-flash-preview",
            contents=user_message,
            config={
                'system_instruction': "You are a helpful assistant.",
                'max_output_tokens': 1024,
            }
        )
        reply = response.text
    except Exception as e:
        print(f"ERROR: Gemini API call failed: {type(e).__name__} - {str(e)}")
        
        # Handle specific Gemini/Google Cloud errors
        error_str = str(e).lower()
        if "429" in error_str or "quota" in error_str:
            reply = "System is busy (Rate Limit). Please try again in a moment."
        elif "401" in error_str or "api_key" in error_str:
            reply = "Invalid API Key configuration."
        else:
            reply = f"Automated response (Technical error: {type(e).__name__})"

    # Persist Assistant Message
    db.session.add(Message(session_id=session.id, role='assistant', content=reply))
    db.session.commit()

    return jsonify({'response': reply, 'session_id': session.id})

# Basic session and history endpoints
@app.route('/sessions', methods=['POST'])
def create_session():
    title = (request.json or {}).get('title')
    s = ChatSession(title=title)
    db.session.add(s)
    db.session.commit()
    return jsonify(s.to_dict()), 201


@app.route('/sessions', methods=['GET'])
def list_sessions():
    sessions = ChatSession.query.order_by(ChatSession.last_visited_at.desc()).all()
    return jsonify([s.to_dict() for s in sessions])


@app.route('/sessions/<int:session_id>/messages', methods=['GET'])
def get_messages(session_id: int):
    s = ChatSession.query.get_or_404(session_id)
    msgs = Message.query.filter_by(session_id=s.id).order_by(Message.created_at.asc()).all()
    return jsonify([m.to_dict() for m in msgs])


if __name__ == '__main__':
    # Run the app on a local host
    app.run(host='0.0.0.0', port=5000)