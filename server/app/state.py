import threading

class AppState:
    def __init__(self):
        self.current_passengers = 0
        self.passenger_lock = threading.Lock()
        self.main_loop = None

state = AppState()
