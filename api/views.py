from rest_framework.views import APIView
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework import status
import datetime

class HealthCheckView(APIView):
    """
    Health check endpoint to monitor service status.
    """
    # No authentication required
    permission_classes = []

    def get(self, request: Request):
        # Basic service information
        health_data = {
            "status": "healthy",
            "service": "python-code-obfuscation",
            "timestamp": datetime.datetime.now().isoformat(),
            "version": "1.0.0"
        }

        return Response(health_data, status=status.HTTP_200_OK)