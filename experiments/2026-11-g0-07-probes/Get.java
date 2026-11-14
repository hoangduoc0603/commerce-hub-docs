import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;

// G0-07: gọi HTTPS bằng HttpClient của JDK, in status hoặc chuỗi nguyên nhân lỗi TLS. Không đụng tới SSLContext:
// trust đến hoàn toàn từ javax.net.ssl.trustStore (JAVA_TOOL_OPTIONS) hoặc cacerts mặc định của JDK.
public class Get {
    public static void main(String[] args) throws Exception {
        HttpClient client = HttpClient.newHttpClient();
        int fail = 0;
        for (String url : args) {
            try {
                HttpResponse<Void> r = client.send(HttpRequest.newBuilder(URI.create(url)).GET().build(),
                        HttpResponse.BodyHandlers.discarding());
                System.out.println("OK   " + r.statusCode() + " " + url);
            } catch (Exception e) {
                fail++;
                System.out.println("FAIL " + url);
                for (Throwable t = e; t != null; t = t.getCause()) {
                    System.out.println("     " + t.getClass().getName() + ": " + t.getMessage());
                }
            }
        }
        System.exit(fail == 0 ? 0 : 1);
    }
}
