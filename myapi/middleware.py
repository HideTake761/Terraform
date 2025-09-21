import logging

logger = logging.getLogger(__name__)

class LoggingMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        logger.debug(f"[REQUEST] {request.method} {request.path}")
        response = self.get_response(request)
        logger.debug(f"[RESPONSE] {request.method} {request.path} - {response.status_code}")
        return response
