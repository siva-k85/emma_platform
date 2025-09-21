Below is an extremely detailed explanation of the ShiftAdmin API URLs and related parameters, along with a breakdown of how they’re used in your application.

---

## ShiftAdmin API URL Breakdown

The ShiftAdmin API endpoint that you work with is provided by ShiftAdmin for retrieving scheduled shifts for physicians. Your URL is constructed dynamically by inserting specific query parameters into a base URL. Let’s deconstruct it piece by piece.

### 1. Base URL

Your base URL (as provided) is:
```
https://www.shiftadmin.com/api_get_scheduled_shifts.php
```

- **Domain:** `www.shiftadmin.com`  
  This is the host for the ShiftAdmin API.
- **Script Name:** `api_get_scheduled_shifts.php`  
  This PHP file on the server is responsible for handling requests and returning the scheduled shift data.

### 2. Query Parameters

Query parameters are added to the base URL using the standard `?` separator followed by key=value pairs. In your URL, these parameters are:

#### a. `validationKey`
- **Key:** `validationKey`
- **Value:** `USACS_ZLTaXAUUWe`  
  This is a secret key used to authenticate and authorize your request to the API. It ensures that only valid users with the correct key can access the data.
- **Purpose:** Acts as a simple token or credential, often configured on the server side to validate the client request.

#### b. `type`
- **Key:** `type`
- **Value:** Either `csv` or `json`  
  This parameter tells the API which format the response should be in.
    - When set to `csv`, the API returns data in comma-separated values format. This is useful if you prefer to work with tabular data using tools like pandas.
    - When set to `json`, the API returns data in JSON format, which is easier to parse directly in Python (using `response.json()`) and integrates seamlessly with JavaScript-based UIs.
- **Your Use Case:** Your application now prefers JSON (since handling JSON avoids the extra complexity of parsing CSV with potential formatting issues).

#### c. `sd`
- **Key:** `sd` (short for "start date")
- **Value Format:** A date string formatted as `YYYY-MM-DD` (e.g., `2025-04-08`)
- **Purpose:** This parameter defines the first day for which you want to retrieve scheduled shifts. The API will return all shifts starting from this date.

#### d. `ed`
- **Key:** `ed` (short for "end date")
- **Value Format:** A date string in the same format (e.g., `2025-05-08`)
- **Purpose:** This parameter defines the last day for which you want to retrieve shifts. Combining `sd` (start date) and `ed` (end date) defines the complete date range that you are querying.

### 3. Putting It All Together

When you construct the URL, you’re essentially concatenating the base URL with the query parameters. For example:

```
https://www.shiftadmin.com/api_get_scheduled_shifts.php?validationKey=USACS_ZLTaXAUUWe&type=json&sd=2025-04-08&ed=2025-05-08
```

Here’s what happens:

1. **Authentication:**  
   The API validates your request using the provided `validationKey`. This key is likely set up on your ShiftAdmin account and must match the server’s records.

2. **Response Format:**  
   By specifying `type=json`, you ensure the response is formatted as JSON, allowing your Python code to easily call `response.json()` to parse the data.

3. **Date Range:**  
   The parameters `sd=2025-04-08` and `ed=2025-05-08` tell the API to return all scheduled shifts within that one-month window. Any scheduled shift outside that range will be excluded.

### 4. How the API Call is Handled in Your Code

In your application (for example, in your Streamlit file), the URL is built dynamically—often the start and end dates are taken from user input or session state. Your code typically does something like this:

```python
# Define key and base URL (these may also be stored in .env or secrets)
validation_key = "USACS_ZLTaXAUUWe"
base_url = "https://www.shiftadmin.com/api_get_scheduled_shifts.php"

# Get the start and end dates from session state or user input (defaults provided)
start_date = st.session_state.get("api_start_date", "2025-04-08")
end_date = st.session_state.get("api_end_date", "2025-05-08")

# Build the URL with query parameters. Using type=json returns JSON output.
api_url = f"{base_url}?validationKey={validation_key}&type=json&sd={start_date}&ed={end_date}"

st.markdown(f"Fetching from: `{api_url}`")

# When the fetch button is clicked, the URL is requested and data is parsed
if st.button("Fetch ShiftAdmin Data (JSON)"):
    response = requests.get(api_url, timeout=30)
    response.raise_for_status()
    shift_json = response.json()
    if shift_json.get("status") == "success":
        shifts_data = shift_json["data"]["scheduledShifts"]
        st.session_state["shiftadmin_shifts"] = shifts_data
        st.success(f"Successfully fetched {len(shifts_data)} shifts.")
        st.dataframe(pd.DataFrame(shifts_data))
    else:
        st.error(f"API error: {shift_json.get('message', 'Unknown error')}")
```

### 5. Additional Considerations

- **Error Handling:**  
  Your code checks for HTTP errors using `response.raise_for_status()` and then inspects the returned JSON to ensure the `status` field is `"success"`. This prevents issues if the API key is invalid, or the date range produces no results.

- **Configuration Management:**  
  Ideally, the `validationKey`, `base_url`, and default `sd` and `ed` values are stored in a configuration file or environment variables (loaded via `.env` or Streamlit secrets). This makes maintenance easier and improves security.

- **Data Flow:**  
  Once the JSON data is fetched, it’s stored in `st.session_state["shiftadmin_shifts"]` so that the matching process (in a separate part of your app) can access the data without needing to re-fetch it. This separation of concerns keeps your API fetching code modular.

- **Fallback Options:**  
  In some cases you might need to support CSV format. However, JSON is generally preferred for web applications because of its simplicity and native compatibility with Python’s `json` module.

---

## Summary

- **Base URL:**  
  `https://www.shiftadmin.com/api_get_scheduled_shifts.php`

- **Query Parameters:**
    - `validationKey=USACS_ZLTaXAUUWe`: Authenticates the request.
    - `type=json`: Specifies the response format as JSON.
    - `sd=2025-04-08`: Start date of the shift range query.
    - `ed=2025-05-08`: End date of the query.

- **Dynamic URL Construction:**  
  The final URL is built with string formatting and is used by your code to fetch data from ShiftAdmin. Error handling is in place to catch HTTP and JSON parsing errors.

This breakdown should provide the exact details you need regarding the ShiftAdmin API URLs and its parameters as used in your application. 