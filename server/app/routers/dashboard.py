from fastapi import APIRouter, Response
from fastapi.responses import HTMLResponse
from app import state, constants
import sqlite3
from core.config import settings

router = APIRouter(prefix="", tags=["Dashboard"])

@router.get("/dashboard", response_class=HTMLResponse)
async def dashboard():
    # Get recent events from SQLite
    try:
        with sqlite3.connect(settings.DB_FILE) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT bus_mac, count, timestamp FROM passenger_history ORDER BY timestamp DESC LIMIT 20")
            recent = cursor.fetchall()
    except Exception as e:
        print(f"DB Error: {e}")
        recent = []

    rows_html = ""
    for row in recent:
        mac, count, timestamp = row
        rows_html += f"""
            <tr>
                <td>{timestamp}</td><td>{mac}</td><td>{count}</td>
            </tr>
        """

    html = f"""
    <!DOCTYPE html>
    <html>
    <head><title>Bus Passenger Counter</title>
    <meta http-equiv="refresh" content="5">
    <style>
        body {{ font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; max-width: 900px; margin: 40px auto; background: #f4f7f9; color: #333; }}
        .header {{ text-align: center; margin-bottom: 30px; }}
        h1 {{ color: #1a73e8; margin-bottom: 10px; }}
        .count-card {{ background: white; border-radius: 12px; padding: 30px; box-shadow: 0 4px 12px rgba(0,0,0,0.1); text-align: center; margin-bottom: 30px; }}
        .count-label {{ font-size: 1.2em; color: #5f6368; text-transform: uppercase; letter-spacing: 1px; }}
        .count-value {{ font-size: 5em; font-weight: bold; color: #1a73e8; margin: 10px 0; }}
        .seats-info {{ font-size: 1.1em; color: #34a853; font-weight: 500; }}
        table {{ width: 100%; border-collapse: collapse; background: white; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 12px rgba(0,0,0,0.1); }}
        th {{ background: #1a73e8; color: white; padding: 15px; text-align: left; }}
        td {{ padding: 15px; border-bottom: 1px solid #eee; }}
        .enter {{ background-color: rgba(52, 168, 83, 0.05); }}
        .exit {{ background-color: rgba(234, 67, 53, 0.05); }}
        .badge {{ padding: 5px 10px; border-radius: 20px; font-size: 0.8em; font-weight: bold; }}
        .badge-enter {{ background: #e6f4ea; color: #1e8e3e; }}
        .badge-exit {{ background: #fce8e6; color: #d93025; }}
    </style>
    </head>
    <body>
        <div class="header">
            <h1>🚌 SUT Smart Bus Dashboard</h1>
            <p>Real-time passenger monitoring and analytics</p>
        </div>
        
        <div class="count-card">
            <div class="count-label">Current Passengers</div>
            <div class="count-value">{state.state.current_passengers}</div>
            <div class="seats-info">Available Seats: {max(0, constants.TOTAL_SEATS - state.state.current_passengers)} / {constants.TOTAL_SEATS}</div>
        </div>

        <table>
            <thead>
                <tr><th>Timestamp</th><th>Bus MAC</th><th>Current Count</th></tr>
            </thead>
            <tbody>
                {rows_html}
            </tbody>
        </table>
    </body>
    </html>
    """
    return html

@router.get("/count")
async def get_count():
    with state.state.passenger_lock:
        return {"passengers": state.state.current_passengers}
