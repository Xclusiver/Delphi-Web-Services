@echo off
cls
echo Test JSON:
curl -i -X GET http://localhost:9000/api/data
echo.
echo.
echo Test 404:
curl -i -X GET http://localhost:9000
echo.
echo ===================================================
echo   TESTY ZAKONCZONE
echo ===================================================
pause